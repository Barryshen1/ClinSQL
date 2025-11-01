WITH los_data AS (
  SELECT
    DATE_DIFF(DATE(admissions.dischtime), DATE(admissions.admittime), DAY) AS los
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` admissions
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` patients
    ON admissions.subject_id = patients.subject_id
  JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` diag
    ON admissions.hadm_id = diag.hadm_id
  JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` d_diag
    ON diag.icd_code = d_diag.icd_code AND diag.icd_version = d_diag.icd_version
  WHERE
    patients.gender = 'F'
    AND patients.anchor_age BETWEEN 84 AND 94
    AND diag.seq_num = 1
    AND (
      d_diag.long_title LIKE '%gastrointestinal hemorrhage%'
      OR d_diag.long_title LIKE '%upper gastrointestinal hemorrhage%'
      OR d_diag.long_title LIKE '%upper GI hemorrhage%'
    )
)
SELECT
  PERCENTILE_CONT(los, 0.25) OVER() AS q1,
  PERCENTILE_CONT(los, 0.75) OVER() AS q3,
  PERCENTILE_CONT(los, 0.75) OVER() - PERCENTILE_CONT(los, 0.25) OVER() AS iqr
FROM los_data
LIMIT 1;