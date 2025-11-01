WITH PatientCohort AS (
  SELECT DISTINCT
    a.hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` AS a
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` AS p
    ON a.subject_id = p.subject_id
  JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` AS d
    ON a.hadm_id = d.hadm_id
  JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` AS di
    ON d.icd_code = di.icd_code AND d.icd_version = di.icd_version
  WHERE
    p.gender = 'F'
    AND p.anchor_age BETWEEN 72 AND 82
    AND a.admission_type = 'EMERGENCY'
    AND d.seq_num = 1 -- Principal diagnosis
    AND di.long_title LIKE '%pancreatitis%' -- Check for pancreatitis diagnosis
    AND a.hospital_expire_flag = 0 -- Discharged patients
)
SELECT
  COUNT(hadm_id) AS total_admissions
FROM PatientCohort;