WITH male_patients_43_53 AS (
  SELECT
    p.subject_id,
    p.gender,
    p.anchor_age,
    a.hadm_id
  FROM
    `physionet-data.mimiciv_3_1_hosp.patients` p
  JOIN
    `physionet-data.mimiciv_3_1_hosp.admissions` a
  ON
    p.subject_id = a.subject_id
  WHERE
    p.gender = 'M'
    AND p.anchor_age BETWEEN 43 AND 53
),

warfarin_prescriptions AS (
  SELECT
    pres.subject_id,
    pres.hadm_id,
    pres.starttime,
    pres.stoptime,
    TIMESTAMP_DIFF(pres.stoptime, pres.starttime, DAY) AS duration_days
  FROM
    `physionet-data.mimiciv_3_1_hosp.prescriptions` pres
  JOIN
    male_patients_43_53 mp
  ON
    pres.subject_id = mp.subject_id
    AND pres.hadm_id = mp.hadm_id
  WHERE
    LOWER(pres.drug) LIKE '%warfarin%'
    AND pres.stoptime IS NOT NULL
)

SELECT
  AVG(duration_days) AS avg_warfarin_duration_days
FROM
  warfarin_prescriptions
WHERE
  duration_days > 0;  -- Exclude prescriptions with 0 or negative duration;