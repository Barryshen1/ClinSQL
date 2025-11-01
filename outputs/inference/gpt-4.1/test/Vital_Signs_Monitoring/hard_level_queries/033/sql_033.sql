WITH instability_item AS (
  SELECT itemid
  FROM `physionet-data.mimiciv_3_1_icu.d_items`
  WHERE LOWER(label) LIKE '%instability score%'
),

-- Step 1: Female ICU patients aged 51-61
female_icu AS (
  SELECT
    icu.subject_id,
    icu.hadm_id,
    icu.stay_id,
    icu.intime,
    icu.outtime,
    icu.los
  FROM `physionet-data.mimiciv_3_1_icu.icustays` icu
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` pat
    ON icu.subject_id = pat.subject_id
  WHERE pat.gender = 'F'
    AND pat.anchor_age BETWEEN 51 AND 61
),

-- Step 2: Identify those on invasive mechanical ventilation in first 48h
vent_stays AS (
  SELECT DISTINCT f.stay_id
  FROM female_icu f
  JOIN `physionet-data.mimiciv_3_1_icu.procedureevents` proc
    ON f.stay_id = proc.stay_id
  WHERE
    LOWER(proc.ordercategorydescription) LIKE '%ventilation%'
    AND LOWER(proc.ordercategorydescription) LIKE '%invasive%'
    AND proc.starttime <= DATETIME_ADD(f.intime, INTERVAL 48 HOUR)
),

-- Step 3: Get instability scores in first 48h
instability_scores AS (
  SELECT
    f.stay_id,
    MAX(c.valuenum) AS max_instability_score
  FROM female_icu f
  JOIN vent_stays v ON f.stay_id = v.stay_id
  JOIN instability_item i ON TRUE
  JOIN `physionet-data.mimiciv_3_1_icu.chartevents` c
    ON f.stay_id = c.stay_id
    AND c.itemid = i.itemid
    AND c.charttime BETWEEN f.intime AND DATETIME_ADD(f.intime, INTERVAL 48 HOUR)
    AND c.valuenum IS NOT NULL
  GROUP BY f.stay_id
),

-- Step 4: Add LOS and mortality
instability_with_outcomes AS (
  SELECT
    s.stay_id,
    s.max_instability_score,
    f.los,
    a.hospital_expire_flag
  FROM instability_scores s
  JOIN female_icu f ON s.stay_id = f.stay_id
  JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a
    ON f.hadm_id = a.hadm_id
),

-- Step 5: Calculate percentile for score 80
percentile_calc AS (
  SELECT
    COUNTIF(max_instability_score < 80) AS below_80,
    COUNT(*) AS total
  FROM instability_with_outcomes
),

-- Step 6: Find 90th percentile cutoff
decile_calc AS (
  SELECT
    APPROX_QUANTILES(max_instability_score, 10)[OFFSET(9)] AS decile_cutoff
  FROM instability_with_outcomes
),

-- Step 7: Outcomes for top decile
top_decile AS (
  SELECT
    los,
    hospital_expire_flag
  FROM instability_with_outcomes, decile_calc
  WHERE max_instability_score >= decile_calc.decile_cutoff
)

-- Final output
SELECT
  -- Part 1: Percentile of instability score 80
  SAFE_DIVIDE((SELECT below_80 FROM percentile_calc), (SELECT total FROM percentile_calc)) * 100 AS percentile_of_80,
  -- Part 2: Top decile outcomes
  (SELECT COUNT(*) FROM top_decile) AS top_decile_n,
  (SELECT AVG(los) FROM top_decile) AS top_decile_avg_los,
  (SELECT APPROX_QUANTILES(los, 2)[OFFSET(1)] FROM top_decile) AS top_decile_median_los,
  (SELECT SAFE_DIVIDE(SUM(CAST(hospital_expire_flag AS INT64)), COUNT(*)) FROM top_decile) AS top_decile_mortality_rate;