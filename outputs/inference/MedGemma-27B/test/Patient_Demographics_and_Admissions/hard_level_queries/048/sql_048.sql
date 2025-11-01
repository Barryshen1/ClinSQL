WITH PatientCohort AS (
  SELECT DISTINCT
    a.hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` AS a
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` AS p
    ON a.subject_id = p.subject_id
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` AS d
    ON a.hadm_id = d.hadm_id
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` AS di
    ON d.icd_code = di.icd_code AND d.icd_version = di.icd_version
  WHERE
    p.gender = 'F'
    AND p.anchor_age >= 79
    AND p.anchor_age <= 89
    AND a.admission_type = 'EMERGENCY'
    AND a.insurance = 'Medicare'
    AND d.seq_num = 1 -- Principal diagnosis
    AND di.long_title LIKE '%pneumonia%'
)
SELECT
  COUNT(hadm_id) AS total_admissions
FROM PatientCohort;