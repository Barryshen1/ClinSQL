WITH male_patients_86_96 AS (
  SELECT
    p.subject_id,
    p.anchor_age,
    p.gender
  FROM
    `physionet-data.mimiciv_3_1_hosp.patients` p
  WHERE
    p.gender = 'M'
    AND p.anchor_age BETWEEN 86 AND 96
),

digoxin_prescriptions AS (
  SELECT
    a.subject_id,
    pr.starttime,
    pr.stoptime,
    TIMESTAMP_DIFF(pr.stoptime, pr.starttime, SECOND) / 3600 AS duration_hours
  FROM
    `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN
    `physionet-data.mimiciv_3_1_hosp.prescriptions` pr
  ON
    a.hadm_id = pr.hadm_id
  JOIN
    male_patients_86_96 mp
  ON
    a.subject_id = mp.subject_id
  WHERE
    LOWER(pr.drug) LIKE '%digoxin%'
    AND pr.stoptime IS NOT NULL
)

SELECT
  PERCENTILE_CONT(duration_hours, 0.25) OVER() AS q1,
  PERCENTILE_CONT(duration_hours, 0.5) OVER() AS median,
  PERCENTILE_CONT(duration_hours, 0.75) OVER() AS q3,
  PERCENTILE_CONT(duration_hours, 0.75) OVER() - PERCENTILE_CONT(duration_hours, 0.25) OVER() AS iqr
FROM
  digoxin_prescriptions
LIMIT 1;