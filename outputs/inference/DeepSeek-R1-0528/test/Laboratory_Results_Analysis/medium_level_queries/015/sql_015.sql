WITH acs_admissions AS (
  SELECT DISTINCT
    adm.subject_id,
    adm.hadm_id,
    adm.admittime,
    p.anchor_year,
    p.anchor_age
  FROM
    `physionet-data.mimiciv_3_1_hosp.admissions` adm
    INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` p 
      ON adm.subject_id = p.subject_id
    INNER JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` diag 
      ON adm.hadm_id = diag.hadm_id
  WHERE
    p.gender = 'F'
    AND (
      (diag.icd_version = 9 AND 
        (diag.icd_code LIKE '410%' OR 
         diag.icd_code = '411.1' OR 
         diag.icd_code = '411.81'))
      OR
      (diag.icd_version = 10 AND 
        (diag.icd_code LIKE 'I21%' OR 
         diag.icd_code LIKE 'I22%' OR 
         diag.icd_code = 'I20.0' OR 
         diag.icd_code LIKE 'I24.0%' OR 
         diag.icd_code LIKE 'I24.1%' OR 
         diag.icd_code LIKE 'I24.8%' OR 
         diag.icd_code LIKE 'I24.9%'))
    )
    AND EXTRACT(YEAR FROM adm.admittime) - (p.anchor_year - p.anchor_age) BETWEEN 88 AND 98
),
first_troponin AS (
  SELECT
    aa.hadm_id,
    le.valuenum AS troponin_value
  FROM
    acs_admissions aa
    INNER JOIN `physionet-data.mimiciv_3_1_hosp.labevents` le 
      ON aa.hadm_id = le.hadm_id
  WHERE
    le.itemid = 51003  -- Troponin T
  QUALIFY
    ROW_NUMBER() OVER (PARTITION BY aa.hadm_id ORDER BY le.charttime) = 1
    AND le.valuenum > 0.01
),
quartiles AS (
  SELECT
    APPROX_QUANTILES(troponin_value, 4) AS arr
  FROM
    first_troponin
)
SELECT
  arr[OFFSET(2)] AS median,  -- 50th percentile
  arr[OFFSET(3)] - arr[OFFSET(1)] AS iqr  -- IQR = Q3 - Q1
FROM
  quartiles;