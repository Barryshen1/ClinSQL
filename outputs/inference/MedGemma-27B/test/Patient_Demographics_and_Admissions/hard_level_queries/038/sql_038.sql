WITH PatientInfo AS (
  SELECT
    p.subject_id,
    p.gender,
    p.anchor_age,
    a.admission_type,
    a.admission_location,
    a.transfertime
  FROM
    `physionet-data.mimiciv_3_1_hosp.patients` AS p
  INNER JOIN
    `physionet-data.mimiciv_3_1_hosp.admissions` AS a
    ON p.subject_id = a.subject_id
  WHERE
    p.gender = 'M'
    AND p.anchor_age BETWEEN 90 AND 100
    AND a.admission_type = 'TRANSFER'
    AND a.admission_location = 'TRANSFER FROM HOSPITAL'
), DiagnosisInfo AS (
  SELECT
    a.subject_id,
    a.hadm_id,
    d.icd_code
  FROM
    `physionet-data.mimiciv_3_1_hosp.admissions` AS a
  INNER JOIN
    `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` AS d
    ON a.subject_id = d.subject_id AND a.hadm_id = d.hadm_id
  WHERE
    d.seq_num = 1
    AND (
      (
        d.icd_version = 9 AND d.icd_code = '585.6'
      ) OR (
        d.icd_version = 10 AND d.icd_code = 'N18.6'
      )
    )
)
SELECT
  COUNT(DISTINCT a.hadm_id) AS number_of_admissions
FROM
  `physionet-data.mimiciv_3_1_hosp.admissions` AS a
INNER JOIN
  PatientInfo AS pi
  ON a.subject_id = pi.subject_id
INNER JOIN
  DiagnosisInfo AS di
  ON a.subject_id = di.subject_id AND a.hadm_id = di.hadm_id;