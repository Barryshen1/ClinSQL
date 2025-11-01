WITH stroke_admissions AS (
  SELECT 
    DATETIME_DIFF(adm.dischtime, adm.admittime, HOUR) / 24.0 AS los_days
  FROM `physionet-data.mimiciv_3_1_hosp.patients` p
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` adm
    ON p.subject_id = adm.subject_id
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` diag
    ON adm.hadm_id = diag.hadm_id
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` d_icd
    ON diag.icd_code = d_icd.icd_code 
    AND diag.icd_version = d_icd.icd_version
  WHERE 
    p.gender = 'F'
    AND p.anchor_age BETWEEN 71 AND 81
    AND diag.seq_num = 1  -- Primary diagnosis
    AND LOWER(d_icd.long_title) LIKE '%cerebral infarction%'
)
SELECT 
  q_arr[OFFSET(1)] AS q25,
  q_arr[OFFSET(3)] AS q75,
  q_arr[OFFSET(3)] - q_arr[OFFSET(1)] AS iqr
FROM (
  SELECT APPROX_QUANTILES(los_days, 4) AS q_arr
  FROM stroke_admissions
);