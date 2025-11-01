WITH PatientCohort AS (
  SELECT DISTINCT
    p.subject_id,
    p.gender,
    p.anchor_age,
    a.admittime,
    a.admission_type,
    a.admission_location,
    d.long_title AS diagnosis_title,
    d.icd_code
  FROM
    `physionet-data.mimiciv_3_1_hosp.patients` AS p
  INNER JOIN
    `physionet-data.mimiciv_3_1_hosp.admissions` AS a ON p.subject_id = a.subject_id
  INNER JOIN
    `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` AS diag ON a.hadm_id = diag.hadm_id
  INNER JOIN
    `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` AS d ON diag.icd_code = d.icd_code
  WHERE
    p.gender = 'F'
    AND p.anchor_age BETWEEN 68 AND 78
    AND a.admission_type = 'EMERGENCY'
    AND a.admission_location = 'EMERGENCY DEPARTMENT'
    AND diag.seq_num = 1 -- Principal diagnosis
    AND (
      d.long_title LIKE '%hemorrhagic stroke%' OR d.long_title LIKE '%intracerebral hemorrhage%' OR d.long_title LIKE '%subarachnoid hemorrhage%' OR d.long_title LIKE '%hemorrhage%'
    )
    AND a.dischtime IS NOT NULL -- Documented discharge
)
SELECT
  COUNT(DISTINCT subject_id) AS number_of_patients
FROM
  PatientCohort;