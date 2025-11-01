WITH PatientInfo AS (
  SELECT
    p.subject_id,
    p.gender,
    p.anchor_age,
    a.admittime
  FROM
    `physionet-data.mimiciv_3_1_hosp.patients` AS p
  JOIN
    `physionet-data.mimiciv_3_1_hosp.admissions` AS a
    ON p.subject_id = a.subject_id
  WHERE
    p.gender = 'F'
    AND p.anchor_age BETWEEN 43 AND 53
    AND a.admission_location = 'EMERGENCY'
), DiagnosisInfo AS (
  SELECT
    a.subject_id,
    a.hadm_id,
    d.icd_code
  FROM
    `physionet-data.mimiciv_3_1_hosp.admissions` AS a
  JOIN
    `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` AS d
    ON a.subject_id = d.subject_id AND a.hadm_id = d.hadm_id
  WHERE
    d.seq_num = 1
    AND d.icd_code LIKE '560%'
), InsuranceInfo AS (
  SELECT
    a.subject_id,
    a.hadm_id,
    a.insurance
  FROM
    `physionet-data.mimiciv_3_1_hosp.admissions` AS a
  WHERE
    a.insurance = 'Medicare'
)
SELECT
  COUNT(DISTINCT a.hadm_id)
FROM
  `physionet-data.mimiciv_3_1_hosp.admissions` AS a
JOIN
  PatientInfo AS pi
  ON a.subject_id = pi.subject_id
JOIN
  DiagnosisInfo AS di
  ON a.subject_id = di.subject_id AND a.hadm_id = di.hadm_id
JOIN
  InsuranceInfo AS ii
  ON a.subject_id = ii.subject_id AND a.hadm_id = ii.hadm_id
WHERE
  a.hospital_expire_flag = 0
  AND a.dischtime IS NOT NULL;