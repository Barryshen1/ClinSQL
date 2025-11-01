WITH
-- 1) Identify MI admissions
mi_admissions AS (
  SELECT
    di.subject_id,
    di.hadm_id,
    1 AS mi_flag
  FROM
    `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` di
    JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` dd
      ON di.icd_code = dd.icd_code
     AND di.icd_version = dd.icd_version
  WHERE
    LOWER(dd.long_title) LIKE '%myocardial infarction%'
  GROUP BY
    di.subject_id,
    di.hadm_id
),
-- 2) Pull and categorize all ICU temperature measurements for our cohort
temps AS (
  SELECT
    ce.subject_id,
    ce.hadm_id,
    ce.stay_id,
    ce.valuenum AS temp_c,
    CASE
      WHEN ce.valuenum < 36 THEN '<36'
      WHEN ce.valuenum < 38 THEN '36-37.9'
      ELSE '>=38'
    END AS temp_category
  FROM
    `physionet-data.mimiciv_3_1_icu.chartevents` ce
    JOIN `physionet-data.mimiciv_3_1_icu.d_items` di
      ON ce.itemid = di.itemid
    JOIN `physionet-data.mimiciv_3_1_icu.icustays` icu
      ON ce.subject_id = icu.subject_id
     AND ce.hadm_id    = icu.hadm_id
     AND ce.stay_id    = icu.stay_id
    JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
      ON ce.subject_id = p.subject_id
  WHERE
    p.gender = 'F'
    AND p.anchor_age BETWEEN 89 AND 99
    AND LOWER(di.label) LIKE '%temp%'        -- catch temperature measurements
    AND ce.valuenum IS NOT NULL
    AND ce.valueuom = 'C'                    -- Celsius only
    AND ce.charttime BETWEEN icu.intime AND icu.outtime
),
-- 3) Attach MI flag (default 0 if no MI in that hadm_id)
temps_mi AS (
  SELECT
    t.*,
    COALESCE(m.mi_flag, 0) AS mi_flag
  FROM
    temps t
    LEFT JOIN mi_admissions m
      ON t.subject_id = m.subject_id
     AND t.hadm_id    = m.hadm_id
)
-- 4) Aggregate per category, using APPROX_QUANTILES for percentiles
, agg AS (
  SELECT
    temp_category,
    COUNT(*) AS measurement_count,
    COUNT(DISTINCT subject_id) AS patient_count,
    ROUND(AVG(temp_c), 2) AS mean_temp,
    APPROX_QUANTILES(temp_c, 100) AS quantiles,
    SAFE_DIVIDE(
      COUNT(DISTINCT CASE WHEN mi_flag = 1 THEN subject_id END),
      COUNT(DISTINCT subject_id)
    ) AS mi_rate
  FROM
    temps_mi
  GROUP BY
    temp_category
)
SELECT
  temp_category,
  measurement_count,
  patient_count,
  mean_temp,
  quantiles[OFFSET(25)] AS temp_25th,
  quantiles[OFFSET(50)] AS median_temp,
  quantiles[OFFSET(75)] AS temp_75th,
  mi_rate
FROM
  agg
ORDER BY
  temp_category;