WITH female_patients_42_52 AS (
  SELECT
    p.subject_id,
    p.anchor_age,
    p.anchor_year,
    a.hadm_id,
    a.admittime,
    a.dischtime
  FROM
    `physionet-data.mimiciv_3_1_hosp.patients` p
  JOIN
    `physionet-data.mimiciv_3_1_hosp.admissions` a
  ON
    p.subject_id = a.subject_id
  WHERE
    p.gender = 'F'
    AND p.anchor_age BETWEEN 42 AND 52
),

amiodarone_prescriptions AS (
  SELECT
    p.subject_id,
    p.hadm_id,
    p.starttime,
    p.stoptime,
    TIMESTAMP_DIFF(p.stoptime, p.starttime, HOUR) AS duration_hours
  FROM
    `physionet-data.mimiciv_3_1_hosp.prescriptions` p
  JOIN
    female_patients_42_52 fp
  ON
    p.subject_id = fp.subject_id AND p.hadm_id = fp.hadm_id
  WHERE
    LOWER(p.drug) LIKE '%amiodarone%'
    AND p.starttime BETWEEN fp.admittime AND fp.dischtime
    AND p.stoptime BETWEEN fp.admittime AND fp.dischtime
    AND p.stoptime IS NOT NULL
)

SELECT
  PERCENTILE_CONT(duration_hours, 0.25) OVER() AS percentile_25_duration_hours
FROM
  amiodarone_prescriptions
LIMIT 1;