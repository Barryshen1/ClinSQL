WITH temp_itemids AS (
  SELECT itemid
  FROM `physionet-data.mimiciv_3_1_icu.d_items`
  WHERE LOWER(label) LIKE '%temp%' AND LOWER(label) LIKE '%c%'
),

-- Step 2: Get male ICU stays aged 85-95
male_elderly_stays AS (
  SELECT icu.stay_id, icu.subject_id, icu.hadm_id
  FROM `physionet-data.mimiciv_3_1_icu.icustays` icu
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` pat
    ON icu.subject_id = pat.subject_id
  WHERE pat.gender = 'M'
    AND pat.anchor_age BETWEEN 85 AND 95
),

-- Step 3: For each stay, calculate average temperature in Celsius
stay_avg_temp AS (
  SELECT
    s.stay_id,
    AVG(c.valuenum) AS avg_temp
  FROM male_elderly_stays s
  JOIN `physionet-data.mimiciv_3_1_icu.chartevents` c
    ON s.subject_id = c.subject_id
    AND s.hadm_id = c.hadm_id
    AND s.stay_id = c.stay_id
  WHERE c.itemid IN (SELECT itemid FROM temp_itemids)
    AND c.valuenum IS NOT NULL
  GROUP BY s.stay_id
  HAVING COUNT(*) > 0 -- exclude stays with no temp records
),

-- Step 4: Calculate percentile rank of 36.0°C
percentile AS (
  SELECT
    COUNTIF(avg_temp <= 36.0) AS num_leq_36,
    COUNT(*) AS total_stays
  FROM stay_avg_temp
)

SELECT
  SAFE_DIVIDE(num_leq_36, total_stays) * 100 AS percentile_rank_36C
FROM percentile;