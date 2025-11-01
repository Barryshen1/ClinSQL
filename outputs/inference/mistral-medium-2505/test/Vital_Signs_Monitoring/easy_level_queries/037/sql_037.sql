WITH
-- Get female patients aged 89-99
female_patients AS (
  SELECT
    subject_id
  FROM
    `physionet-data.mimiciv_3_1_hosp.patients`
  WHERE
    gender = 'F'
    AND anchor_age BETWEEN 89 AND 99
),

-- Get ICU stays for these patients
icu_stays AS (
  SELECT
    s.subject_id,
    s.hadm_id,
    s.stay_id,
    s.intime,
    TIMESTAMP_ADD(s.intime, INTERVAL 24 HOUR) AS first_24h_end
  FROM
    `physionet-data.mimiciv_3_1_icu.icustays` s
  JOIN
    female_patients p ON s.subject_id = p.subject_id
),

-- Get MAP measurements in the first 24 hours of ICU stay
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
    icu_stays s ON c.subject_id = s.subject_id AND c.hadm_id = s.hadm_id AND c.stay_id = s.stay_id
  WHERE
    c.itemid = 220050  -- MAP itemid
    AND c.charttime BETWEEN s.intime AND s.first_24h_end
    AND c.valuenum IS NOT NULL
),

-- Calculate average MAP per patient
avg_map_per_patient AS (
  SELECT
    subject_id,
    AVG(map_value) AS avg_map
  FROM
    map_measurements
  GROUP BY
    subject_id
)

-- Final average MAP across all patients
SELECT
  AVG(avg_map) AS average_map_first_24h
FROM
  avg_map_per_patient;