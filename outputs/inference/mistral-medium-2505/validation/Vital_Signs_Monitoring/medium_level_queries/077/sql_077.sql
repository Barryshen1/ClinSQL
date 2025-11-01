WITH female_patients AS (
  SELECT
    subject_id,
    gender,
    anchor_age,
    anchor_year
  FROM
    `physionet-data.mimiciv_3_1_hosp.patients`
  WHERE
    gender = 'F'
    AND anchor_age BETWEEN 42 AND 52
),

icu_stays AS (
  SELECT
    s.subject_id,
    s.hadm_id,
    s.stay_id,
    s.intime,
    s.outtime
  FROM
    `physionet-data.mimiciv_3_1_icu.icustays` s
  JOIN
    female_patients p ON s.subject_id = p.subject_id
),

heart_rate_measurements AS (
  SELECT
    ce.subject_id,
    ce.hadm_id,
    ce.stay_id,
    ce.charttime,
    ce.valuenum AS heart_rate
  FROM
    `physionet-data.mimiciv_3_1_icu.chartevents` ce
  JOIN
    `physionet-data.mimiciv_3_1_icu.d_items` di ON ce.itemid = di.itemid
  WHERE
    di.label = 'Heart Rate'
    AND ce.valuenum IS NOT NULL
    AND ce.valuenum > 0
    AND ce.valuenum < 300  -- Exclude unrealistic heart rates
),

avg_heart_rate_per_stay AS (
  SELECT
    hs.stay_id,
    AVG(hrm.heart_rate) AS avg_heart_rate
  FROM
    icu_stays hs
  JOIN
    heart_rate_measurements hrm ON hs.stay_id = hrm.stay_id
  GROUP BY
    hs.stay_id
  HAVING
    COUNT(hrm.heart_rate) > 0  -- Ensure at least one measurement
),

percentile_ranks AS (
  SELECT
    stay_id,
    avg_heart_rate,
    PERCENT_RANK() OVER (ORDER BY avg_heart_rate) AS percentile
  FROM
    avg_heart_rate_per_stay
),

target_percentile AS (
  SELECT
    COUNT(*) AS cohort_size,
    MAX(percentile) AS percentile
  FROM
    percentile_ranks
  WHERE
    avg_heart_rate <= 90  -- Find percentile for 90 bpm
)

SELECT
  cohort_size,
  percentile
FROM
  target_percentile;