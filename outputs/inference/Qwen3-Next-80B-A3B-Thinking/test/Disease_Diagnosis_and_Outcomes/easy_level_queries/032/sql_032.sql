WITH filtered_data AS (
  SELECT
    TIMESTAMP_DIFF(admissions.dischtime, admissions.admittime, DAY) AS los
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` admissions
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` patients
    ON admissions.subject_id = patients.subject_id
  JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` diag
    ON admissions.hadm_id = diag.hadm_id
  JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` d_diag
    ON diag.icd_code = d_diag.icd_code AND diag.icd_version = d_diag.icd_version
  WHERE
    patients.gender = 'M'
    AND patients.anchor_age BETWEEN 81 AND 91
    AND diag.seq_num = 1
    AND (
      LOWER(d_diag.long_title) LIKE '%acute kidney injury%'
      OR LOWER(d_diag.long_title) LIKE '%acute renal failure%'
      OR LOWER(d_diag.long_title) LIKE '%acute kidney failure%'
    )
)
SELECT
  PERCENTILE_CONT(los, 0.75) OVER() - PERCENTILE_CONT(los, 0.25) OVER() AS iqr
FROM filtered_data
LIMIT 1;