WITH male_patients_62_72 AS (
  SELECT
    subject_id
  FROM
    `physionet-data.mimiciv_3_1_hosp.patients`
  WHERE
    gender = 'M'
    AND anchor_age BETWEEN 62 AND 72
),

amiodarone_prescriptions AS (
  SELECT
    pr.subject_id,
    pr.hadm_id,
    TIMESTAMP_DIFF(pr.stoptime, pr.starttime, DAY) AS prescription_duration_days
  FROM
    `physionet-data.mimiciv_3_1_hosp.prescriptions` pr
  JOIN
    `physionet-data.mimiciv_3_1_hosp.admissions` a
    ON pr.hadm_id = a.hadm_id
  JOIN
    male_patients_62_72 mp
    ON a.subject_id = mp.subject_id
  WHERE
    LOWER(pr.drug) LIKE '%amiodarone%'
    AND pr.stoptime IS NOT NULL
    AND pr.stoptime > pr.starttime
)

SELECT
  PERCENTILE_DISC(prescription_duration_days, 0.25) OVER() AS q1,
  PERCENTILE_DISC(prescription_duration_days, 0.75) OVER() AS q3,
  PERCENTILE_DISC(prescription_duration_days, 0.75) OVER() - PERCENTILE_DISC(prescription_duration_days, 0.25) OVER() AS iqr
FROM
  amiodarone_prescriptions
LIMIT 1;