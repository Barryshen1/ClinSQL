WITH IndexAdmissions AS (
  SELECT
    a.hadm_id,
    a.subject_id,
    a.admittime,
    a.admission_type,
    a.admission_location,
    p.gender,
    p.anchor_age,
    d.long_title AS diagnosis_title,
    d.icd_version
  FROM
    `physionet-data.mimiciv_3_1_hosp.admissions` AS a
    INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` AS p ON a.subject_id = p.subject_id
    INNER JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` AS diag ON a.hadm_id = diag.hadm_id AND diag.seq_num = 1
    INNER JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` AS d ON diag.icd_code = d.icd_code AND diag.icd_version = d.icd_version
  WHERE
    a.admission_location = 'EMERGENCY'
    AND p.gender = 'F'
    AND p.anchor_age BETWEEN 70 AND 80
    AND d.long_title LIKE '%pancreatitis%'
    AND diag.seq_num = 1
)
SELECT
  COUNT(hadm_id) AS total_index_admissions
FROM
  IndexAdmissions;