WITH resp_rate_itemid AS (
  SELECT itemid
  FROM `physionet-data.mimiciv_3_1_icu.d_items`
  WHERE LOWER(label) = 'respiratory rate'
),

-- Step 2: Build cohort of females aged 38-48 in ICU
cohort AS (
  SELECT
    p.subject_id,
    p.anchor_age,
    p.gender,
    i.hadm_id,
    i.stay_id,
    i.intime,
    i.outtime
  FROM `physionet-data.mimiciv_3_1_hosp.patients` p
  INNER JOIN `physionet-data.mimiciv_3_1_icu.icustays` i
    ON p.subject_id = i.subject_id
  WHERE p.gender = 'F'
    AND p.anchor_age BETWEEN 38 AND 48
),

-- Step 3: Get respiratory rate measurements in first 24h of ICU stay
resp_rate_24h AS (
  SELECT
    c.subject_id,
    c.anchor_age,
    c.gender,
    c.hadm_id,
    c.stay_id,
    ce.charttime,
    ce.valuenum
  FROM cohort c
  INNER JOIN `physionet-data.mimiciv_3_1_icu.chartevents` ce
    ON c.subject_id = ce.subject_id
    AND c.hadm_id = ce.hadm_id
    AND c.stay_id = ce.stay_id
  INNER JOIN resp_rate_itemid rri
    ON ce.itemid = rri.itemid
  WHERE ce.valuenum IS NOT NULL
    AND ce.valuenum > 0
    AND ce.charttime >= c.intime
    AND ce.charttime < DATETIME_ADD(c.intime, INTERVAL 24 HOUR)
),

-- Step 4: Get max respiratory rate per ICU stay
max_resp_rate_per_stay AS (
  SELECT
    subject_id,
    anchor_age,
    gender,
    hadm_id,
    stay_id,
    MAX(valuenum) AS max_resp_rate_24h
  FROM resp_rate_24h
  GROUP BY subject_id, anchor_age, gender, hadm_id, stay_id
)

-- Step 5: Output for 43-year-old female and cohort
SELECT
  subject_id,
  anchor_age,
  gender,
  hadm_id,
  stay_id,
  max_resp_rate_24h,
  CASE WHEN anchor_age = 43 THEN 'target_43yo_female' ELSE 'cohort' END AS group_label
FROM max_resp_rate_per_stay
ORDER BY group_label DESC, max_resp_rate_24h DESC;