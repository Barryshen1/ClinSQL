WITH cohort AS (
  SELECT 
    a.subject_id, a.hadm_id, a.admittime, a.dischtime, a.deathtime, p.dod, p.anchor_age, a.admission_location,
    MAX(CASE WHEN d.seq_num = 1 THEN 1 ELSE 0 END) as has_primary_lgib  -- Ensure primary dx filter
  FROM `physionet-data.mimiciv_3_1_hosp.patients` p
  JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a ON p.subject_id = a.subject_id
  JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d ON a.hadm_id = d.hadm_id
  WHERE p.gender = 'F'
    AND p.anchor_age BETWEEN 70 AND 80
    AND (
      (d.icd_version = 9 AND d.icd_code IN ('5693', '56212', '56213', '4552'))
      OR
      (d.icd_version = 10 AND d.icd_code IN ('K625', 'K922'))
    )
  GROUP BY a.subject_id, a.hadm_id, a.admittime, a.dischtime, a.deathtime, p.dod, p.anchor_age, a.admission_location
  HAVING SUM(CASE WHEN d.seq_num = 1 THEN 1 ELSE 0 END) > 0  -- At least one primary dx match
),

first_labs AS (
  SELECT 
    le.subject_id, le.hadm_id, le.itemid, le.valuenum,
    ROW_NUMBER() OVER (PARTITION BY le.subject_id, le.hadm_id, le.itemid ORDER BY le.charttime ASC) AS rn
  FROM `physionet-data.mimiciv_3_1_hosp.labevents` le
  JOIN cohort c ON le.subject_id = c.subject_id AND le.hadm_id = c.hadm_id
  WHERE le.charttime >= c.admittime
    AND le.charttime <= TIMESTAMP_ADD(c.admittime, INTERVAL 24 HOUR)
    AND le.valuenum IS NOT NULL
    AND le.itemid IN (51006, 51222)  -- BUN, Hemoglobin
),

admission_labs AS (
  SELECT 
    subject_id, hadm_id,
    MAX(CASE WHEN itemid = 51006 AND rn = 1 THEN valuenum END) AS first_bun,
    MAX(CASE WHEN itemid = 51222 AND rn = 1 THEN valuenum END) AS first_hgb
  FROM first_labs
  GROUP BY subject_id, hadm_id
),

major_comps AS (
  SELECT DISTINCT 
    d.subject_id, d.hadm_id,
    1 AS has_major_comp
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
  JOIN cohort c ON d.hadm_id = c.hadm_id
  WHERE (
    (d.icd_version = 9 AND (
      d.icd_code LIKE '584%' OR  -- AKI
      d.icd_code LIKE '410%' OR  -- MI
      (d.icd_code LIKE '43%' OR d.icd_code LIKE '434%') OR  -- Stroke
      (d.icd_code LIKE '038%' OR d.icd_code LIKE '785.5%') OR  -- Sepsis/shock
      d.icd_code = '99592'  -- SIRS
    ))
    OR
    (d.icd_version = 10 AND (
      d.icd_code LIKE 'N17%' OR  -- AKI
      d.icd_code LIKE 'I21%' OR  -- MI
      d.icd_code LIKE 'I63%' OR  -- Stroke
      (d.icd_code LIKE 'A41%' OR d.icd_code LIKE 'R57%')  -- Sepsis/shock
    ))
  )
),

base AS (
  SELECT 
    c.*,
    al.first_bun, al.first_hgb,
    COALESCE(mc.has_major_comp, 0) AS has_major_comp,
    TIMESTAMP_DIFF(c.dischtime, c.admittime, DAY) AS los,
    CASE 
      WHEN c.dod IS NOT NULL AND DATE(c.dod) <= DATE_ADD(DATE(c.admittime), INTERVAL 90 DAY) 
      THEN 1 ELSE 0 
    END AS ninety_day_mort,
    -- Composite risk score (higher = higher risk)
    COALESCE(al.first_bun, 20) + 
    CASE 
      WHEN al.first_hgb IS NULL THEN 8 
      ELSE GREATEST(0, 15 - al.first_hgb) 
    END + 
    CASE WHEN c.admission_location LIKE '%EMERGENCY%' THEN 5 ELSE 0 END + 
    (c.anchor_age - 70) AS risk_score,
    NTILE(5) OVER (ORDER BY (
      COALESCE(al.first_bun, 20) + 
      CASE WHEN al.first_hgb IS NULL THEN 8 ELSE GREATEST(0, 15 - al.first_hgb) END + 
      CASE WHEN c.admission_location LIKE '%EMERGENCY%' THEN 5 ELSE 0 END + 
      (c.anchor_age - 70)
    ) ASC) AS quintile
  FROM cohort c
  LEFT JOIN admission_labs al ON c.hadm_id = al.hadm_id
  LEFT JOIN major_comps mc ON c.hadm_id = mc.hadm_id
  WHERE TIMESTAMP_DIFF(c.dischtime, c.admittime, DAY) > 0  -- Valid LOS
)

SELECT 
  bs.quintile,
  COUNT(*) AS N,
  SAFE_DIVIDE(SUM(bs.ninety_day_mort), COUNT(*)) AS ninety_day_mortality_rate,
  SAFE_DIVIDE(SUM(bs.has_major_comp), COUNT(*)) AS major_complication_rate,
  sl.median_los
FROM base bs
LEFT JOIN (
  SELECT 
    quintile,
    PERCENTILE_CONT(los, 0.5) OVER (PARTITION BY quintile) AS median_los
  FROM base
  WHERE ninety_day_mort = 0
) sl ON bs.quintile = sl.quintile
GROUP BY bs.quintile, sl.median_los
ORDER BY quintile;