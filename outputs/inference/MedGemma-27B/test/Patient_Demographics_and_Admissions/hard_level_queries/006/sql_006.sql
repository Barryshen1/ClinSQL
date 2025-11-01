WITH PatientCohort AS (
  SELECT
    p.subject_id
  FROM
    `physionet-data.mimiciv_3_1_hosp.patients` AS p
  WHERE
    p.gender = 'F'
    AND p.anchor_age BETWEEN 36 AND 46
)
SELECT
  COUNT(DISTINCT a.hadm_id)
FROM
  `physionet-data.mimiciv_3_1_hosp.admissions` AS a
INNER JOIN
  `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` AS d
  ON a.hadm_id = d.hadm_id
INNER JOIN
  PatientCohort AS pc
  ON a.subject_id = pc.subject_id
WHERE
  a.admission_type = 'TRANSFER'
  AND a.insurance = 'Medicare'
  AND d.seq_num = 1
  AND d.icd_code LIKE 'I60%';