WITH PatientCohort AS (
  SELECT DISTINCT
    a.hadm_id
  FROM
    `physionet-data.mimiciv_3_1_hosp.admissions` AS a
  INNER JOIN
    `physionet-data.mimiciv_3_1_hosp.patients` AS p
    ON a.subject_id = p.subject_id
  INNER JOIN
    `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` AS d
    ON a.hadm_id = d.hadm_id
  WHERE
    p.gender = 'F'
    AND p.anchor_age BETWEEN 80 AND 90
    AND a.admission_location = 'EMERGENCY'
    AND d.seq_num = 1
    AND d.icd_code LIKE '730%'
)
SELECT
  COUNT(hadm_id) AS number_of_admissions
FROM
  PatientCohort;