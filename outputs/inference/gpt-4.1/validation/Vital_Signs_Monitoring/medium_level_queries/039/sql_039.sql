WITH map_items AS (
  SELECT itemid
  FROM `physionet-data.mimiciv_3_1_icu.d_items`
  WHERE LOWER(label) LIKE '%mean arterial pressure%' OR LOWER(label) LIKE '%map%'
),

-- Step 2: Get male ICU stays aged 83-93
cohort AS (
  SELECT
    icu.subject_id,
    icu.hadm_id,
    icu.stay_id,
    icu.intime,
    icu.outtime,
    pat.anchor_age,
    pat.gender
  FROM `physionet-data.mimiciv_3_1_icu.icustays` icu
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` pat
    ON icu.subject_id = pat.subject_id
  WHERE pat.gender = 'M'
    AND pat.anchor_age BETWEEN 83 AND 93
),

-- Step 3: Get MAP measurements in first 48h of ICU stay
map_measurements AS (
  SELECT
    c.subject_id,
    c.hadm_id,
    c.stay_id,
    ce.charttime,
    ce.valuenum
  FROM cohort c
  JOIN `physionet-data.mimiciv_3_1_icu.chartevents` ce
    ON c.subject_id = ce.subject_id
    AND c.hadm_id = ce.hadm_id
    AND c.stay_id = ce.stay_id
  JOIN map_items mi
    ON ce.itemid = mi.itemid
  WHERE ce.valuenum IS NOT NULL
    AND ce.valuenum > 0 -- exclude erroneous values
    AND TIMESTAMP_DIFF(ce.charttime, c.intime, HOUR) BETWEEN 0 AND 48
),

-- Step 4: Compute per-stay MAP averages (only stays with >=3 MAP measurements)
stay_map_avg AS (
  SELECT
    subject_id,
    hadm_id,
    stay_id,
    COUNT(*) AS n_map_measurements,
    AVG(valuenum) AS avg_map
  FROM map_measurements
  GROUP BY subject_id, hadm_id, stay_id
  HAVING COUNT(*) >= 3
),

-- Step 5: Identify the target patient (88-year-old male)
target_stays AS (
  SELECT
    s.subject_id,
    s.hadm_id,
    s.stay_id,
    s.avg_map
  FROM stay_map_avg s
  JOIN cohort c
    ON s.subject_id = c.subject_id
    AND s.stay_id = c.stay_id
  WHERE c.anchor_age = 88
    AND c.gender = 'M'
)

-- Step 6: Calculate percentile of target patient's avg_map among cohort
SELECT
  t.subject_id,
  t.stay_id,
  t.avg_map AS target_avg_map,
  ROUND(100.0 * (
    SELECT COUNT(*) FROM stay_map_avg WHERE avg_map <= t.avg_map
  ) / (SELECT COUNT(*) FROM stay_map_avg), 2) AS percentile
FROM target_stays t;