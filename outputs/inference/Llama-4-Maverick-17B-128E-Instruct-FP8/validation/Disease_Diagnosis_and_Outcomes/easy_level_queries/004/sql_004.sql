WITH 
eligible_patients AS (
  SELECT subject_id
  FROM `physionet-data.mimiciv_3_1_hosp.patients`
  WHERE anchor_age BETWEEN 73 AND 83 AND gender = 'M'
),
dka_hhs_admissions AS (
  SELECT DISTINCT diag.hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` diag
  JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` d_icd
    ON diag.icd_code = d_icd.icd_code AND diag.icd_version = d_icd.icd_version
  WHERE diag.seq_num = 1  
    AND diag.icd_version = 10  
    AND d_icd.icd_code IN ('E87.1', 'E87.2')  
),
hospital_los AS (
  SELECT adm.hadm_id, 
         DATETIME_DIFF(adm.dischtime, adm.admittime, HOUR) / 24 AS los_days
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` adm
  JOIN eligible_patients ep ON adm.subject_id = ep.subject_id
  JOIN dka_hhs_admissions dka_hhs ON adm.hadm_id = dka_hhs.hadm_id
)
SELECT 
  APPROX_QUANTILES(los_days, 100)[OFFSET(25)] AS percentile_25_los
FROM hospital_los;