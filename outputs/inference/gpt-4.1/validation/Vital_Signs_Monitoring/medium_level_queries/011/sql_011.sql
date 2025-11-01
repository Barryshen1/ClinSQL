WITH rr_itemids AS (
  -- Get all itemids for Respiratory Rate
  SELECT itemid
  FROM `physionet-data.mimiciv_3_1_icu.d_items`
  WHERE LOWER(label) LIKE '%respiratory rate%'
),

male_icu_stays AS (
  -- Get male ICU stays age 54–64
  SELECT
    icu.subject_id,
    icu.hadm_id,
    icu.stay_id,
    icu.intime,
    icu.outtime
  FROM `physionet-data.mimiciv_3_1_icu.icustays` icu
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` pat
    ON icu.subject_id = pat.subject_id
  WHERE pat.gender = 'M'
    AND pat.anchor_age BETWEEN 54 AND 64
),

rr_first48h AS (
  -- Get RR measurements in first 48h of each ICU stay
  SELECT
    c.subject_id,
    c.hadm_id,
    c.stay_id,
    c.charttime,
    c.valuenum
  FROM `physionet-data.mimiciv_3_1_icu.chartevents` c
  JOIN rr_itemids rri ON c.itemid = rri.itemid
  JOIN male_icu_stays icu
    ON c.subject_id = icu.subject_id
    AND c.hadm_id = icu.hadm_id
    AND c.stay_id = icu.stay_id
  WHERE c.valuenum IS NOT NULL
    AND c.charttime >= icu.intime
    AND c.charttime < TIMESTAMP_ADD(icu.intime, INTERVAL 48 HOUR)
),

per_stay_avg_rr AS (
  -- Calculate per-stay average RR
  SELECT
    stay_id,
    AVG(valuenum) AS avg_rr
  FROM rr_first48h
  GROUP BY stay_id
  HAVING COUNT(valuenum) > 0
),

categorized AS (
  -- Categorize per-stay average RR
  SELECT
    stay_id,
    avg_rr,
    CASE
      WHEN avg_rr < 12 THEN '<12'
      WHEN avg_rr >= 12 AND avg_rr <= 20 THEN '12–20'
      WHEN avg_rr >= 21 AND avg_rr <= 29 THEN '21–29'
      WHEN avg_rr >= 30 THEN '≥30'
      ELSE 'Unknown'
    END AS rr_category
  FROM per_stay_avg_rr
)

SELECT
  rr_category,
  COUNT(*) AS n,
  ROUND(AVG(avg_rr), 2) AS mean_avg_rr,
  ROUND(APPROX_QUANTILES(avg_rr, 2)[OFFSET(1)], 2) AS median_avg_rr,
  ROUND(APPROX_QUANTILES(avg_rr, 4)[OFFSET(1)], 2) AS iqr_25,
  ROUND(APPROX_QUANTILES(avg_rr, 4)[OFFSET(3)], 2) AS iqr_75
FROM categorized
WHERE rr_category != 'Unknown'
GROUP BY rr_category
ORDER BY
  CASE rr_category
    WHEN '<12' THEN 1
    WHEN '12–20' THEN 2
    WHEN '21–29' THEN 3
    WHEN '≥30' THEN 4
    ELSE 5
  END;