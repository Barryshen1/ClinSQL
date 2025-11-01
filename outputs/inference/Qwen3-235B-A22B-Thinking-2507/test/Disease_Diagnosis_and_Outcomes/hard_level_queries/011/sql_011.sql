WITH cohort AS (
  SELECT 
    adm.hadm_id,
    adm.admittime,
    adm.deathtime,
    p.dod
  FROM `physionet-data.mimiciv_3_1_hosp`.admissions adm
  INNER JOIN `physionet-data.mimiciv_3_1_hosp`.patients p
    ON adm.subject_id = p.subject_id
  WHERE p.gender = 'F'
    -- Age calculation: anchor_age + (admission year - anchor_year)
    AND (p.anchor_age + (EXTRACT(YEAR FROM adm.admittime) - p.anchor_year)) BETWEEN 88 AND 98
    -- AMI diagnosis filter (ICD-9: 410%; ICD-10: I21% or I22%)
    AND EXISTS (
      SELECT 1 
      FROM `physionet-data.mimiciv_3_1_hosp`.diagnoses_icd d
      WHERE d.hadm_id = adm.hadm_id
        AND (
          (d.icd_version = 9 AND d.icd_code LIKE '410%')
          OR (d.icd_version = 10 AND (d.icd_code LIKE 'I21%' OR d.icd_code LIKE 'I22%'))
        )
    )
    -- ICU stay requirement
    AND EXISTS (
      SELECT 1
      FROM `physionet-data.mimiciv_3_1_icu`.icustays icu
      WHERE icu.hadm_id = adm.hadm_id
    )
),
outcomes AS (
  SELECT 
    c.hadm_id,
    -- 30-day mortality flag
    CASE 
      WHEN c.deathtime IS NOT NULL AND DATETIME_DIFF(c.deathtime, c.admittime, DAY) <= 30 THEN 1
      WHEN c.dod IS NOT NULL AND DATE_DIFF(DATE(c.dod), DATE(c.admittime), DAY) <= 30 THEN 1
      ELSE 0 
    END AS died_30d,
    -- AKI flag (ICD-9: 5845/5846/5848/5849; ICD-10: N17%)
    MAX(CASE 
      WHEN d.icd_version = 9 AND d.icd_code IN ('5845','5846','5848','5849') THEN 1
      WHEN d.icd_version = 10 AND d.icd_code LIKE 'N17%' THEN 1
      ELSE 0 
    END) AS has_aki,
    -- ARDS flag (ICD-9: 5185/51882-51885; ICD-10: J80)
    MAX(CASE 
      WHEN d.icd_version = 9 AND d.icd_code IN ('5185','51882','51883','51884','51885') THEN 1
      WHEN d.icd_version = 10 AND d.icd_code = 'J80' THEN 1
      ELSE 0 
    END) AS has_ards,
    -- Time to death (days) for decedents
    CASE 
      WHEN c.deathtime IS NOT NULL THEN DATETIME_DIFF(c.deathtime, c.admittime, DAY)
      WHEN c.dod IS NOT NULL THEN DATE_DIFF(DATE(c.dod), DATE(c.admittime), DAY)
      ELSE NULL 
    END AS time_to_death
  FROM cohort c
  LEFT JOIN `physionet-data.mimiciv_3_1_hosp`.diagnoses_icd d
    ON c.hadm_id = d.hadm_id
  GROUP BY c.hadm_id, c.admittime, c.deathtime, c.dod
)
SELECT
  NULL AS avg_composite_risk_percentile,  -- Not defined in data
  AVG(died_30d) AS mortality_30d_rate,
  AVG(has_aki) AS aki_rate,
  AVG(has_ards) AS ards_rate,
  APPROX_QUANTILES(time_to_death, 2)[OFFSET(1)] AS median_survival_decedents_days
FROM outcomes;