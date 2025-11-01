WITH female_icu_patients AS (
  -- Get female patients aged 80-90 with ICU stays
  SELECT
    p.subject_id,
    p.gender,
    p.anchor_age,
    i.hadm_id,
    i.stay_id
  FROM
    `physionet-data.mimiciv_3_1_hosp.patients` p
  JOIN
    `physionet-data.mimiciv_3_1_icu.icustays` i
    ON p.subject_id = i.subject_id
  WHERE
    p.gender = 'F'
    AND p.anchor_age BETWEEN 80 AND 90
),

heart_rate_data AS (
  -- Get heart rate measurements for these patients
  SELECT
    c.subject_id,
    c.hadm_id,
    c.stay_id,
    c.valuenum AS heart_rate
  FROM
    `physionet-data.mimiciv_3_1_icu.chartevents` c
  JOIN
    `physionet-data.mimiciv_3_1_icu.d_items` d
    ON c.itemid = d.itemid
  WHERE
    d.label = 'Heart Rate'
    AND c.valuenum IS NOT NULL
),

avg_heart_rate_per_stay AS (
  -- Calculate average heart rate per ICU stay
  SELECT
    h.stay_id,
    AVG(h.heart_rate) AS avg_heart_rate
  FROM
    heart_rate_data h
  JOIN
    female_icu_patients f
    ON h.subject_id = f.subject_id AND h.stay_id = f.stay_id
  GROUP BY
    h.stay_id
),

percentile_rank_calc AS (
  -- Calculate the percentile rank for 110 bpm
  SELECT
    PERCENT_RANK() OVER (ORDER BY avg_heart_rate) AS percentile_rank,
    avg_heart_rate
  FROM
    avg_heart_rate_per_stay
)

-- Find the percentile rank for 110 bpm
SELECT
  MAX(percentile_rank) AS percentile_for_110_bpm
FROM
  percentile_rank_calc
WHERE
  avg_heart_rate <= 110;