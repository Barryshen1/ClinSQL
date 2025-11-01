WITH
-- Filter male patients aged 57-67
eligible_patients AS (
  SELECT
    subject_id
  FROM
    `physionet-data.mimiciv_3_1_hosp.patients`
  WHERE
    gender = 'M'
    AND anchor_age BETWEEN 57 AND 67
),

-- Get DAPT prescriptions (aspirin + P2Y12 inhibitor)
dapt_prescriptions AS (
  SELECT
    p.subject_id,
    p.hadm_id,
    p.starttime,
    p.stoptime,
    TIMESTAMP_DIFF(p.stoptime, p.starttime, HOUR) AS duration_hours
  FROM
    `physionet-data.mimiciv_3_1_hosp.prescriptions` p
  JOIN
    eligible_patients ep ON p.subject_id = ep.subject_id
  WHERE
    -- Aspirin (common names)
    (LOWER(p.drug) LIKE '%aspirin%'
     -- P2Y12 inhibitors
     OR LOWER(p.drug) LIKE '%clopidogrel%'
     OR LOWER(p.drug) LIKE '%prasugrel%'
     OR LOWER(p.drug) LIKE '%ticagrelor%')
    -- Ensure stoptime is not NULL
    AND p.stoptime IS NOT NULL
),

-- Get one DAPT prescription per admission (first by starttime)
single_dapt_per_admission AS (
  SELECT
    subject_id,
    hadm_id,
    duration_hours
  FROM (
    SELECT
      subject_id,
      hadm_id,
      duration_hours,
      ROW_NUMBER() OVER (PARTITION BY subject_id, hadm_id ORDER BY starttime) AS rn
    FROM
      dapt_prescriptions
  )
  WHERE
    rn = 1
)

-- Calculate IQR of prescription durations
SELECT
  PERCENTILE_CONT(duration_hours, 0.25) OVER() AS q1,
  PERCENTILE_CONT(duration_hours, 0.5) OVER() AS median,
  PERCENTILE_CONT(duration_hours, 0.75) OVER() AS q3,
  PERCENTILE_CONT(duration_hours, 0.75) OVER() - PERCENTILE_CONT(duration_hours, 0.25) OVER() AS iqr
FROM
  single_dapt_per_admission
LIMIT 1;