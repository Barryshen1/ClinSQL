WITH PatientAmiodarone AS (
  SELECT
    p.subject_id,
    rx.starttime,
    rx.stoptime
  FROM
    `physionet-data.mimiciv_3_1_hosp.patients` AS p
  INNER JOIN
    `physionet-data.mimiciv_3_1_hosp.prescriptions` AS rx
    ON p.subject_id = rx.subject_id
  WHERE
    p.gender = 'M'
    AND p.anchor_age BETWEEN 62 AND 72
    AND rx.drug = 'amiodarone'
    AND rx.drug_type = 'Drug'
),
AmiodaroneDuration AS (
  SELECT
    subject_id,
    DATE_DIFF(stoptime, starttime, DAY) AS duration_days
  FROM
    PatientAmiodarone
  WHERE
    stoptime IS NOT NULL
)
SELECT
  PERCENTILE_CONT(duration_days, 0.25) AS q1,
  PERCENTILE_CONT(duration_days, 0.75) AS q3,
  PERCENTILE_CONT(duration_days, 0.75) - PERCENTILE_CONT(duration_days, 0.25) AS IQR
FROM
  AmiodaroneDuration;