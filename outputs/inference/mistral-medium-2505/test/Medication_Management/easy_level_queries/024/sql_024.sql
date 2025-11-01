WITH male_patients_84_94 AS (
  SELECT
    subject_id,
    anchor_age
  FROM
    `physionet-data.mimiciv_3_1_hosp.patients`
  WHERE
    gender = 'M'
    AND anchor_age BETWEEN 84 AND 94
),

dapt_prescriptions AS (
  SELECT
    p.subject_id,
    p.hadm_id,
    p.pharmacy_id,
    p.starttime,
    p.stoptime,
    p.drug,
    TIMESTAMP_DIFF(p.stoptime, p.starttime, SECOND) AS duration_seconds
  FROM
    `physionet-data.mimiciv_3_1_hosp.prescriptions` p
  JOIN
    male_patients_84_94 mp ON p.subject_id = mp.subject_id
  WHERE
    -- Filter for common DAPT drugs (aspirin + P2Y12 inhibitor)
    (LOWER(p.drug) LIKE '%aspirin%' OR LOWER(p.drug) LIKE '%clopidogrel%' OR LOWER(p.drug) LIKE '%ticagrelor%')
    AND p.stoptime IS NOT NULL
)

SELECT
  MAX(duration_seconds / 3600) AS max_duration_hours
FROM
  dapt_prescriptions;