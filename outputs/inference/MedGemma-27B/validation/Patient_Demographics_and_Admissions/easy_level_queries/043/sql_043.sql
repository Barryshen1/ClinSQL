WITH PatientAge AS (
  SELECT
    subject_id,
    anchor_age,
    gender
  FROM
    `physionet-data.mimiciv_3_1_hosp.patients`
),
AdmissionInfo AS (
  SELECT
    a.subject_id,
    a.hadm_id,
    a.hospital_expire_flag,
    p.anchor_age,
    p.gender
  FROM
    `physionet-data.mimiciv_3_1_hosp.admissions` AS a
  INNER JOIN
    PatientAge AS p
    ON a.subject_id = p.subject_id
  WHERE
    p.gender = 'F' AND p.anchor_age BETWEEN 51 AND 61
)
SELECT
  AVG(hospital_expire_flag) AS average_mortality_rate
FROM
  AdmissionInfo;