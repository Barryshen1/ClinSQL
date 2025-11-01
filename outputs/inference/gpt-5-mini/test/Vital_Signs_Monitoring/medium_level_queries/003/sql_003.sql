WITH temp_items AS (
  -- Identify ICU itemids that likely correspond to temperature measurements
  SELECT DISTINCT itemid
  FROM `physionet-data.mimiciv_3_1_icu.d_items`
  WHERE LOWER(label) LIKE '%temp%' OR LOWER(label) LIKE '%temperature%'
),

stay_avg_temps AS (
  -- Per-ICU-stay average temperature during the first 48 hours of the ICU stay
  SELECT
    icu.stay_id,
    icu.subject_id,
    icu.hadm_id,
    AVG(ce.valuenum) AS avg_temp_first48
  FROM `physionet-data.mimiciv_3_1_icu.icustays` icu
  JOIN `physionet-data.mimiciv_3_1_icu.chartevents` ce
    ON ce.stay_id = icu.stay_id
  JOIN temp_items ti
    ON ce.itemid = ti.itemid
  WHERE
    ce.valuenum IS NOT NULL
    AND ce.charttime BETWEEN icu.intime AND TIMESTAMP_ADD(icu.intime, INTERVAL 48 HOUR)
  GROUP BY icu.stay_id, icu.subject_id, icu.hadm_id
),

mi_by_hadm AS (
  -- Flag admissions (hadm_id) that have any diagnosis suggestive of myocardial infarction
  SELECT DISTINCT
    d.hadm_id,
    1 AS had_mi
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
  LEFT JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` dd
    ON d.icd_code = dd.icd_code AND d.icd_version = dd.icd_version
  WHERE
    (dd.long_title IS NOT NULL AND (
        LOWER(dd.long_title) LIKE '%myocardial%' OR
        LOWER(dd.long_title) LIKE '%infarct%' OR
        LOWER(dd.long_title) LIKE '%infarction%'
      ))
),

cohort_stays AS (
  -- Filter to male patients aged 71-81 and join per-stay average temps and MI flag
  SELECT
    s.stay_id,
    s.subject_id,
    s.hadm_id,
    s.avg_temp_first48,
    CASE
      WHEN s.avg_temp_first48 < 36.0 THEN '<36.0'
      WHEN s.avg_temp_first48 BETWEEN 36.0 AND 37.9 THEN '36.0-37.9'
      WHEN s.avg_temp_first48 >= 38.0 THEN '>=38.0'
      ELSE 'UNMAPPED'
    END AS temp_category,
    COALESCE(m.had_mi, 0) AS had_mi
  FROM stay_avg_temps s
  JOIN `physionet-data.mimiciv_3_1_icu.icustays` icu
    ON s.stay_id = icu.stay_id
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON icu.subject_id = p.subject_id
  LEFT JOIN mi_by_hadm m
    ON s.hadm_id = m.hadm_id
  WHERE
    p.gender = 'M'
    AND p.anchor_age BETWEEN 71 AND 81
    -- exclude any stays where avg_temp_first48 is NULL (shouldn't be present due to earlier filter)
    AND s.avg_temp_first48 IS NOT NULL
)

SELECT
  temp_category AS temperature_category,
  COUNT(*) AS n_stays,
  ROUND(AVG(avg_temp_first48), 3) AS mean_of_stay_avg_temp,
  -- Use APPROX_QUANTILES(...,4) to get [min, Q1, median, Q3, max]
  (APPROX_QUANTILES(avg_temp_first48, 4))[OFFSET(1)] AS q1_avg_temp,
  (APPROX_QUANTILES(avg_temp_first48, 4))[OFFSET(2)] AS median_avg_temp,
  (APPROX_QUANTILES(avg_temp_first48, 4))[OFFSET(3)] AS q3_avg_temp,
  -- IQR = Q3 - Q1
  ROUND(
    ( (APPROX_QUANTILES(avg_temp_first48, 4))[OFFSET(3)]
      - (APPROX_QUANTILES(avg_temp_first48, 4))[OFFSET(1)]
    ), 3
  ) AS iqr_avg_temp,
  -- MI rate: fraction of stays in the category with an MI diagnosis during the admission
  ROUND(100.0 * SUM(CAST(had_mi AS INT64)) / COUNT(*), 2) AS mi_rate_percent
FROM cohort_stays
GROUP BY temp_category
ORDER BY
  -- order bins meaningfully
  CASE
    WHEN temp_category = '<36.0' THEN 1
    WHEN temp_category = '36.0-37.9' THEN 2
    WHEN temp_category = '>=38.0' THEN 3
    ELSE 4
  END;