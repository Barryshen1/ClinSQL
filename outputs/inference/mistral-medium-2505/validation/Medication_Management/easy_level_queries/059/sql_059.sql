WITH
-- Filter for hospitalized males aged 38-48
hospitalized_males AS (
  SELECT
    p.subject_id,
    a.hadm_id,
    a.dischtime
  FROM
    `physionet-data.mimiciv_3_1_hosp.patients` p
  JOIN
    `physionet-data.mimiciv_3_1_hosp.admissions` a
  ON
    p.subject_id = a.subject_id
  WHERE
    p.gender = 'M'
    AND p.anchor_age BETWEEN 38 AND 48
),

-- Get ARB prescriptions with duration
arb_prescriptions AS (
  SELECT
    p.subject_id,
    p.hadm_id,
    p.starttime,
    p.stoptime,
    h.dischtime,
    -- Calculate duration in days, using dischtime if stoptime is NULL
    TIMESTAMP_DIFF(
      COALESCE(p.stoptime, h.dischtime),
      p.starttime,
      DAY
    ) AS duration_days
  FROM
    `physionet-data.mimiciv_3_1_hosp.prescriptions` p
  JOIN
    hospitalized_males h
  ON
    p.subject_id = h.subject_id
    AND p.hadm_id = h.hadm_id
  WHERE
    -- List of common ARB drug names (case-insensitive)
    LOWER(p.drug) IN (
      'losartan', 'valsartan', 'irbesartan', 'candesartan',
      'olmesartan', 'telmisartan', 'azilsartan', 'eprosartan'
    )
    -- Ensure stoptime is not before starttime (data quality check)
    AND (p.stoptime IS NULL OR p.stoptime >= p.starttime)
    -- Ensure dischtime is not before starttime (data quality check)
    AND (h.dischtime IS NULL OR h.dischtime >= p.starttime)
)

-- Calculate the 75th percentile of duration_days
SELECT
  PERCENTILE_CONT(duration_days, 0.75) OVER() AS p75_duration_days
FROM
  arb_prescriptions
LIMIT 1;