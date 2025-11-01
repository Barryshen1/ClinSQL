WITH troponin_itemids AS (
  SELECT DISTINCT itemid
  FROM `physionet-data.mimiciv_3_1_hosp.d_labitems`
  WHERE LOWER(label) LIKE '%troponin t%'
    AND category = 'Chemistry'
),
acs_codes AS (
  SELECT DISTINCT icd_code, icd_version
  FROM `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses`
  WHERE icd_version = '10'
    AND icd_code LIKE 'I2%'  -- I20-I25 for ACS/ischemic heart disease
),
cohort_admissions AS (
  SELECT DISTINCT p.subject_id, a.hadm_id, a.admittime
  FROM `physionet-data.mimiciv_3_1_hosp.patients` p
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a
    ON p.subject_id = a.subject_id
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
    ON a.hadm_id = d.hadm_id
  INNER JOIN acs_codes ac
    ON d.icd_code = ac.icd_code AND d.icd_version = ac.icd_version
  WHERE p.gender = 'F'
    AND p.anchor_age BETWEEN 88 AND 98
    AND a.admission_type = 'EMERGENCY'
    AND d.seq_num = 1  -- Primary diagnosis for ACS
),
first_troponin AS (
  SELECT 
    c.subject_id,
    c.hadm_id,
    le.charttime,
    le.valuenum
  FROM cohort_admissions c
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.labevents` le
    ON c.hadm_id = le.hadm_id
  INNER JOIN troponin_itemids ti
    ON le.itemid = ti.itemid
  WHERE le.charttime >= c.admittime
    AND le.valuenum > 0.01
    AND le.valuenum IS NOT NULL
  QUALIFY ROW_NUMBER() OVER (PARTITION BY c.hadm_id ORDER BY le.charttime ASC) = 1
)
SELECT 
  COUNT(*) AS num_admissions,
  APPROX_QUANTILES(valuenum, 4)[OFFSET(2)] AS median_troponin_ngml,
  APPROX_QUANTILES(valuenum, 4)[OFFSET(1)] AS iqr_q1_ngml,
  APPROX_QUANTILES(valuenum, 4)[OFFSET(3)] AS iqr_q3_ngml
FROM first_troponin;