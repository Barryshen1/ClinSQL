WITH PatientCohort AS (
  SELECT DISTINCT
    a.subject_id,
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
    AND p.anchor_age = 43
    AND a.admission_type = 'EMERGENCY'
    AND di.long_title LIKE '%cholecystitis%'
    AND d.seq_num = 1 -- Principal diagnosis
    AND a.admission_location = 'EMERGENCY ROOM' -- Ensure admission is from ED
)
SELECT
  COUNT(hadm_id) AS total_index_admissions
FROM PatientCohort;