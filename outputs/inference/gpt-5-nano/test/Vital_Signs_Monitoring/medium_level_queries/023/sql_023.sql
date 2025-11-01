WITH cohort AS (
  SELECT
    i.subject_id,
    i.hadm_id,
    i.stay_id,
    i.intime
  FROM `physionet-data.mimiciv_3_1_icu.icustays` AS i
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` AS p
    ON i.subject_id = p.subject_id
  WHERE LOWER(p.gender) = 'female'
    AND p.anchor_age BETWEEN 62 AND 72
),

temp_raw AS (
  SELECT
    c.subject_id,
    c.hadm_id,
    ce.valuenum
  FROM cohort AS c
  JOIN `physionet-data.mimiciv_3_1_icu.chartevents` AS ce
    ON ce.stay_id = c.stay_id
  JOIN `physionet-data.mimiciv_3_1_icu.d_items` AS di
    ON ce.itemid = di.itemid
  WHERE (
          LOWER(di.label) LIKE '%temperature%'
          OR LOWER(di.label) LIKE '%temp%'
        )
    AND ce.charttime >= c.intime
    AND ce.charttime < TIMESTAMP_ADD(c.intime, INTERVAL 24 HOUR)
    AND ce.valuenum IS NOT NULL
),

categorized AS (
  SELECT
    CASE
      WHEN valuenum < 36.0 THEN '<36.0'
      WHEN valuenum <= 37.9 THEN '36.0-37.9'
      ELSE '>=38.0'
    END AS temp_category,
    valuenum
  FROM temp_raw
),

quantiles_cat AS (
  SELECT temp_category, APPROX_QUANTILES(valuenum, 100) AS quantiles
  FROM categorized
  GROUP BY temp_category
),

summary_cat AS (
  SELECT
    c.temp_category,
    COUNT(*) AS n_measurements,
    AVG(c.valuenum) AS mean_temp,
    q.quantiles[OFFSET(50)] AS median_temp,
    (q.quantiles[OFFSET(75)] - q.quantiles[OFFSET(25)]) AS iqr_temp
  FROM categorized c
  JOIN quantiles_cat q ON c.temp_category = q.temp_category
  GROUP BY c.temp_category, q.quantiles[OFFSET(50)], (q.quantiles[OFFSET(75)] - q.quantiles[OFFSET(25)])
),

overall_values AS (
  SELECT valuenum FROM temp_raw
),
overall_stat AS (
  SELECT
    COUNT(*) AS n_measurements,
    AVG(valuenum) AS mean_temp,
    APPROX_QUANTILES(valuenum, 100) AS quantiles
  FROM overall_values
),
summary_overall AS (
  SELECT
    'Overall' AS temp_category,
    o.n_measurements,
    o.mean_temp,
    o.quantiles[OFFSET(50)] AS median_temp,
    (o.quantiles[OFFSET(75)] - o.quantiles[OFFSET(25)]) AS iqr_temp
  FROM overall_stat o
),

aki_flags AS (
  SELECT DISTINCT c.subject_id
  FROM cohort AS c
  JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` AS di
    ON c.subject_id = di.subject_id AND c.hadm_id = di.hadm_id
  WHERE di.icd_code LIKE 'N17%'
     OR di.icd_code LIKE '584%'
),
aki_calc AS (
  SELECT
    (SELECT COUNT(*) FROM aki_flags) AS aki_cases,
    (SELECT COUNT(*) FROM cohort) AS total_cohort
)

SELECT
  s.temp_category,
  s.n_measurements,
  s.mean_temp,
  s.median_temp,
  s.iqr_temp,
  a.aki_cases,
  a.total_cohort,
  SAFE_DIVIDE(a.aki_cases, a.total_cohort) AS aki_rate
FROM (
  SELECT * FROM summary_cat
  UNION ALL
  SELECT * FROM summary_overall
) AS s
CROSS JOIN aki_calc a
ORDER BY CASE WHEN s.temp_category = 'Overall' THEN 1 ELSE 0 END,
         s.temp_category;