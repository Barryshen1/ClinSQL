WITH systolic_items AS (
  SELECT itemid
  FROM `physionet-data.mimiciv_3_1_icu.d_items`
  WHERE LOWER(label) LIKE '%systolic%'
    AND LOWER(category) LIKE '%blood pressure%'
),
icu_demo AS (
  SELECT 
    icu.subject_id,
    icu.hadm_id,
    icu.stay_id,
    icu.intime,
    icu.outtime,
    p.gender,
    p.anchor_age + EXTRACT(YEAR FROM icu.intime) - p.anchor_year AS age
  FROM `physionet-data.mimiciv_3_1_icu.icustays` icu
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON icu.subject_id = p.subject_id
  WHERE p.gender = 'F'
)
, first24h_bp AS (
  SELECT
    icu_demo.stay_id,
    ce.valuenum
  FROM icu_demo
  JOIN systolic_items si
    ON TRUE
  JOIN `physionet-data.mimiciv_3_1_icu.chartevents` ce
    ON icu_demo.stay_id = ce.stay_id
    AND ce.itemid = si.itemid
    AND ce.valuenum IS NOT NULL
    AND ce.valuenum > 0
    AND ce.charttime BETWEEN icu_demo.intime 
                         AND TIMESTAMP_ADD(icu_demo.intime, INTERVAL 24 HOUR)
  WHERE icu_demo.age BETWEEN 65 AND 75
)
, grouped AS (
  SELECT
    CASE
      WHEN valuenum < 140 THEN '<140'
      WHEN valuenum BETWEEN 140 AND 159 THEN '140-159'
      ELSE '>=160'
    END AS sbp_category,
    COUNT(*) AS n_measurements,
    AVG(valuenum) AS mean_sbp,
    APPROX_QUANTILES(valuenum, 4) AS quants
  FROM first24h_bp
  GROUP BY sbp_category
)
SELECT
  sbp_category,
  n_measurements,
  mean_sbp,
  quants[OFFSET(2)] AS median_sbp,
  quants[OFFSET(1)] AS q1_sbp,
  quants[OFFSET(3)] AS q3_sbp,
  quants[OFFSET(3)] - quants[OFFSET(1)] AS iqr_sbp
FROM grouped
ORDER BY sbp_category;