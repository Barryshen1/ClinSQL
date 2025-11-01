WITH PatientInfo AS (
  SELECT
    subject_id
  FROM
    `physionet-data.mimiciv_3_1_hosp.patients`
  WHERE
    gender = 'F' AND anchor_age BETWEEN 90 AND 100
),
AdmissionInfo AS (
  SELECT
    hadm_id
  FROM
    `physionet-data.mimiciv_3_1_hosp.admissions`
  WHERE
    subject_id IN (
      SELECT
        subject_id
      FROM
        PatientInfo
    )
),
PrescriptionInfo AS (
  SELECT
    p.subject_id,
    p.hadm_id,
    p.drug,
    p.starttime,
    p.stoptime
  FROM
    `physionet-data.mimiciv_3_1_hosp.prescriptions` AS p
  WHERE
    p.drug LIKE '%thiazide%'
    AND p.hadm_id IN (
      SELECT
        hadm_id
      FROM
        AdmissionInfo
    )
),
DurationInfo AS (
  SELECT
    subject_id,
    hadm_id,
    drug,
    starttime,
    stoptime,
    TIMESTAMP_DIFF(stoptime, starttime, DAY) AS duration_days
  FROM
    PrescriptionInfo
),
Percentiles AS (
  SELECT
    APPROX_QUANTILES(duration_days, 4)[OFFSET(1)] AS q1,
    APPROX_QUANTILES(duration_days, 4)[OFFSET(2)] AS q3
  FROM
    DurationInfo
)
SELECT
  q1,
  q3,
  q3 - q1 AS IQR
FROM
  Percentiles;