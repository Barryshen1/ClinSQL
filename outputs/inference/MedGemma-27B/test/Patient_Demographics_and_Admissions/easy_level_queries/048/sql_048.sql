WITH PatientInfo AS (
  SELECT
    subject_id,
    gender,
    anchor_age
  FROM
    `physionet-data.mimiciv_3_1_hosp.patients`
  WHERE
    gender = 'F' AND anchor_age BETWEEN 79 AND 89
), AdmissionInfo AS (
  SELECT
    p.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    a.deathtime,
    a.hospital_expire_flag
  FROM
    `physionet-data.mimiciv_3_1_hosp.admissions` AS a
  INNER JOIN
    PatientInfo AS p
    ON a.subject_id = p.subject_id
  WHERE
    a.admission_type = 'EMERGENCY'
), DiagnosisInfo AS (
  SELECT
    a.hadm_id,
    d.icd_code
  FROM
    `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` AS d
  INNER JOIN
    AdmissionInfo AS a
    ON d.hadm_id = a.hadm_id
  WHERE
    d.icd_version = 9 AND d.icd_code LIKE '428%'
), FirstAdmission AS (
  SELECT
    a.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    a.deathtime,
    a.hospital_expire_flag
  FROM
    AdmissionInfo AS a
  INNER JOIN
    DiagnosisInfo AS d
    ON a.hadm_id = d.hadm_id
  WHERE
    a.admittime = (
      SELECT
        MIN(admittime)
      FROM
        `physionet-data.mimiciv_3_1_hosp.admissions` AS sub_a
      WHERE
        sub_a.subject_id = a.subject_id
    )
)
SELECT
  PERCENTILE_CONT(0.25, los) AS q1,
  PERCENTILE_CONT(0.75, los) AS q3,
  PERCENTILE_CONT(0.75, los) - PERCENTILE_CONT(0.25, los) AS iqr
FROM (
  SELECT
    hadm_id,
    (
      CASE
        WHEN deathtime IS NOT NULL
        THEN TIMESTAMP_DIFF(deathtime, admittime, DAY)
        ELSE TIMESTAMP_DIFF(dischtime, admittime, DAY)
      END
    ) AS los
  FROM
    FirstAdmission
);