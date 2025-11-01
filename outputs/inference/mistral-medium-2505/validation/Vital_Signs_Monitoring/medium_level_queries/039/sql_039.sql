WITH
-- Get male patients aged 83-93
male_patients AS (
  SELECT
    subject_id
  FROM
    `physionet-data.mimiciv_3_1_hosp.patients`
  WHERE
    gender = 'M'
    AND anchor_age BETWEEN 83 AND 93
),

-- Get ICU stays for these patients
icu_stays AS (
  SELECT
    s.subject_id,
    s.hadm_id,
    s.stay_id,
    s.intime AS icu_intime,
    s.outtime AS icu_outtime
  FROM
    `physionet-data.mimiciv_3_1_icu.icustays` s
  JOIN
    male_patients p ON s.subject_id = p.subject_id
),

-- Get MAP measurements (itemid 220050 is MAP in MIMIC-IV)
map_measurements AS (
  SELECT
    c.subject_id,
    c.hadm_id,
    c.stay_id,
    c.charttime,
    c.valuenum AS map_value
  FROM
    `physionet-data.mimiciv_3_1_icu.chartevents` c
  JOIN
    `physionet-data.mimiciv_3_1_icu.d_items` d ON c.itemid = d.itemid
  WHERE
    d.label = 'Mean Arterial Pressure'
    AND c.valuenum IS NOT NULL
),

-- Filter MAP measurements within first 48 hours of ICU stay
early_map AS (
  SELECT
    m.subject_id,
    m.hadm_id,
    m.stay_id,
    m.charttime,
    m.map_value
  FROM
    map_measurements m
  JOIN
    icu_stays s ON m.subject_id = s.subject_id AND m.hadm_id = s.hadm_id AND m.stay_id = s.stay_id
  WHERE
    TIMESTAMP_DIFF(m.charttime, s.icu_intime, HOUR) <= 48
),

-- Count MAP measurements per stay and filter stays with >=3 measurements
valid_stays AS (
  SELECT
    stay_id,
    COUNT(*) AS map_count
  FROM
    early_map
  GROUP BY
    stay_id
  HAVING
    COUNT(*) >= 3
),

-- Calculate average MAP per valid stay
avg_map_per_stay AS (
  SELECT
    e.stay_id,
    AVG(e.map_value) AS avg_map
  FROM
    early_map e
  JOIN
    valid_stays v ON e.stay_id = v.stay_id
  GROUP BY
    e.stay_id
)

-- Calculate the percentile rank for a MAP of 60 mmHg
SELECT
  ROUND(
    (SELECT COUNT(*) FROM avg_map_per_stay WHERE avg_map < 60) /
    (SELECT COUNT(*) FROM avg_map_per_stay) * 100,
    2
  ) AS percentile_rank
FROM
  avg_map_per_stay
LIMIT 1;