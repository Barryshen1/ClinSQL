WITH PatientAge AS (
  SELECT
    subject_id,
    anchor_age
  FROM
    `physionet-data.mimiciv_3_1_hosp.patients`
  WHERE
    gender = 'M' AND anchor_age BETWEEN 73 AND 83
),
FirstAdmission AS (
  SELECT
    subject_id,
    MIN(admittime) AS first_admittime
  FROM
    `physionet-data.mimiciv_3_1_hosp.admissions`
  GROUP BY
    subject_id
),
AdmissionMortality AS (
  SELECT
    a.subject_id,
    a.hadm_id,
    a.hospital_expire_flag
  FROM
    `physionet-data.mimiciv_3_1_hosp.admissions` AS a
  INNER JOIN
    FirstAdmission AS fa
    ON a.subject_id = fa.subject_id AND a.admittime = fa.first_admittime
  INNER JOIN
    PatientAge AS pa
    ON a.subject_id = pa.subject_id
)
SELECT
  PERCENTILE_CONT(0.25, hospital_expire_flag)
FROM
  AdmissionMortality;