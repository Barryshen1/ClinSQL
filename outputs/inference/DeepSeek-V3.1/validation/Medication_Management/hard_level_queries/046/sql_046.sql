WITH cohort AS (
  SELECT 
    adm.subject_id, 
    adm.hadm_id, 
    adm.admittime, 
    adm.dischtime, 
    adm.hospital_expire_flag,
    DATETIME_DIFF(adm.dischtime, adm.admittime, DAY) AS los_days,
    pat.anchor_age
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` adm
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` pat
    ON adm.subject_id = pat.subject_id
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` diag
    ON adm.hadm_id = diag.hadm_id
  WHERE pat.gender = 'F'
    AND pat.anchor_age BETWEEN 45 AND 55
    AND (
      diag.icd_code LIKE 'T0[0-7]%' OR  -- Trauma codes T00-T07
      diag.icd_code LIKE 'S%' OR        -- Injury codes S series
      diag.icd_code LIKE 'T1[4-9]%'     -- External cause codes
    )
    AND diag.icd_version = 10
  GROUP BY adm.subject_id, adm.hadm_id, adm.admittime, adm.dischtime, 
           adm.hospital_expire_flag, pat.anchor_age
),

medications AS (
  SELECT 
    emar.hadm_id,
    COUNT(DISTINCT emar_detail.product_code) AS complexity_score
  FROM `physionet-data.mimiciv_3_1_hosp.emar` emar
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.emar_detail` emar_detail
    ON emar.emar_id = emar_detail.emar_id
    AND emar.emar_seq = emar_detail.emar_seq
  INNER JOIN cohort c
    ON emar.hadm_id = c.hadm_id
  WHERE emar.charttime <= DATETIME_ADD(c.admittime, INTERVAL 7 DAY)
    AND emar_detail.product_code IS NOT NULL
  GROUP BY emar.hadm_id
),

cohort_with_score AS (
  SELECT 
    c.*,
    COALESCE(m.complexity_score, 0) AS complexity_score
  FROM cohort c
  LEFT JOIN medications m
    ON c.hadm_id = m.hadm_id
),

tertiles AS (
  SELECT 
    hadm_id,
    complexity_score,
    NTILE(3) OVER (ORDER BY complexity_score) AS tertile
  FROM cohort_with_score
),

readmissions AS (
  SELECT 
    adm1.hadm_id,
    COUNT(DISTINCT adm2.hadm_id) > 0 AS readmitted_30d
  FROM cohort_with_score adm1
  LEFT JOIN `physionet-data.mimiciv_3_1_hosp.admissions` adm2
    ON adm1.subject_id = adm2.subject_id
    AND adm2.admittime > adm1.dischtime
    AND adm2.admittime <= DATETIME_ADD(adm1.dischtime, INTERVAL 30 DAY)
    AND adm2.hadm_id != adm1.hadm_id  -- Ensure different admission
  GROUP BY adm1.hadm_id
)

SELECT 
  t.tertile,
  COUNT(*) AS admissions,
  AVG(t.complexity_score) AS mean_score,
  MIN(t.complexity_score) AS min_score,
  MAX(t.complexity_score) AS max_score,
  AVG(c.los_days) AS mean_los_days,
  100.0 * SUM(c.hospital_expire_flag) / COUNT(*) AS mortality_pct,
  100.0 * SUM(CAST(r.readmitted_30d AS INT64)) / COUNT(*) AS readmission_30d_pct
FROM tertiles t
INNER JOIN cohort_with_score c
  ON t.hadm_id = c.hadm_id
LEFT JOIN readmissions r
  ON t.hadm_id = r.hadm_id
GROUP BY t.tertile
ORDER BY t.tertile;