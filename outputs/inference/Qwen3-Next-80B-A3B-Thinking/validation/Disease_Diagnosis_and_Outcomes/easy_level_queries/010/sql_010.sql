SELECT PERCENTILE_CONT(0.25) WITHIN GROUP (ORDER BY los_days) AS percentile_25
FROM (
  SELECT
    DATE_DIFF(admissions.dischtime, admissions.admittime, DAY) AS los_days
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` AS admissions
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` AS patients
    ON admissions.subject_id = patients.subject_id
  JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` AS diag
    ON admissions.hadm_id = diag.hadm_id
    AND diag.seq_num = 1
  JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` AS d_diag
    ON diag.icd_code = d_diag.icd_code
    AND diag.icd_version = d_diag.icd_version
  WHERE
    patients.gender = 'F'
    AND (patients.anchor_age + (EXTRACT(YEAR FROM admissions.admittime) - patients.anchor_year)) BETWEEN 49 AND 59
    AND diag.icd_code = 'J44.1'
    AND diag.icd_version = 10
) AS los_data;