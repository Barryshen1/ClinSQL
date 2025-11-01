WITH cohort AS (
  -- Base cohort: males 67-77 with primary ADHF admission
  SELECT 
    p.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    a.hospital_expire_flag,
    DATE_DIFF(a.dischtime, a.admittime, DAY) AS los_days,
    CASE WHEN DATE_DIFF(a.dischtime, a.admittime, DAY) <= 7 THEN '<=7' ELSE '>7' END AS los_group
  FROM 
    `physionet-data.mimiciv_3_1_hosp.patients` p
  INNER JOIN 
    `physionet-data.mimiciv_3_1_hosp.admissions` a
    ON p.subject_id = a.subject_id
  INNER JOIN 
    `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
    ON a.hadm_id = d.hadm_id
  WHERE 
    p.gender = 'M'
    AND SAFE_CAST(p.anchor_age AS INT64) BETWEEN 67 AND 77
    AND d.seq_num = 1
    AND d.icd_version = '10'
    AND d.icd_code LIKE 'I50%'  -- Primary heart failure (ADHF)
    AND a.dischtime IS NOT NULL  -- Exclude ongoing admissions
),

ckd_diag AS (
  -- CKD diagnoses per admission
  SELECT 
    hadm_id,
    1 AS has_ckd
  FROM 
    `physionet-data.mimiciv_3_1_hosp.diagnoses_icd`
  WHERE 
    icd_version = '10'
    AND icd_code LIKE 'N18%'
  GROUP BY hadm_id
),

diabetes_diag AS (
  -- Diabetes diagnoses per admission
  SELECT 
    hadm_id,
    1 AS has_diabetes
  FROM 
    `physionet-data.mimiciv_3_1_hosp.diagnoses_icd`
  WHERE 
    icd_version = '10'
    AND (icd_code LIKE 'E10%' OR icd_code LIKE 'E11%' OR icd_code LIKE 'E13%')
  GROUP BY hadm_id
)

SELECT 
  c.los_group,
  CASE WHEN i.stay_id IS NOT NULL THEN 'Yes' ELSE 'No' END AS day1_icu,
  ROUND(AVG(c.hospital_expire_flag) * 100, 1) AS mortality_pct,
  ROUND(AVG(COALESCE(ckd.has_ckd, 0)) * 100, 1) AS ckd_pct,
  ROUND(AVG(COALESCE(diabetes.has_diabetes, 0)) * 100, 1) AS diabetes_pct
FROM 
  cohort c
LEFT JOIN 
  ckd_diag ckd
  ON c.hadm_id = ckd.hadm_id
LEFT JOIN 
  diabetes_diag diabetes
  ON c.hadm_id = diabetes.hadm_id
LEFT JOIN (
  -- Day-1 ICU: first ICU stay within 1 day of admission
  SELECT DISTINCT
    s.hadm_id,
    s.stay_id
  FROM 
    `physionet-data.mimiciv_3_1_icu.icustays` s
  INNER JOIN 
    cohort c2
    ON s.hadm_id = c2.hadm_id
  WHERE 
    s.intime <= TIMESTAMP_ADD(c2.admittime, INTERVAL 1 DAY)
    AND s.first_careunit IN ('Medical ICU', 'Surgical ICU', 'Cardiac Care Unit', 'Trauma/Surgical ICU')
) i
  ON c.hadm_id = i.hadm_id
GROUP BY 
  c.los_group,
  CASE WHEN i.stay_id IS NOT NULL THEN 'Yes' ELSE 'No' END
ORDER BY 
  c.los_group,
  CASE WHEN i.stay_id IS NOT NULL THEN 'Yes' ELSE 'No' END;