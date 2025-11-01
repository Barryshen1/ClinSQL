WITH temp_items AS (
  SELECT itemid
  FROM `physionet-data.mimiciv_3_1_icu.d_items`
  WHERE LOWER(label) LIKE '%temperature%'
    AND param_type = 'Numeric'
),

filtered_patients AS (
  SELECT subject_id
  FROM `physionet-data.mimiciv_3_1_hosp.patients`
  WHERE gender = 'F'
    AND anchor_age BETWEEN 62 AND 72
),

icu_temp_first24 AS (
  SELECT
    ce.subject_id,
    ce.stay_id,
    ce.valuenum AS temperature,
    CASE
      WHEN ce.valuenum < 36.0 THEN '<36.0'
      WHEN ce.valuenum BETWEEN 36.0 AND 37.9 THEN '36.0–37.9'
      WHEN ce.valuenum >= 38.0 THEN '≥38.0'
      ELSE NULL
    END AS temp_category
  FROM `physionet-data.mimiciv_3_1_icu.chartevents` ce
  JOIN `physionet-data.mimiciv_3_1_icu.icustays` icu
    ON ce.stay_id = icu.stay_id
  JOIN filtered_patients fp
    ON ce.subject_id = fp.subject_id
  WHERE ce.itemid IN (SELECT itemid FROM temp_items)
    AND ce.valuenum IS NOT NULL
    AND ce.charttime BETWEEN icu.intime AND DATETIME_ADD(icu.intime, INTERVAL 1 DAY)
),

aki_patients AS (
  SELECT DISTINCT hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` di
  JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` d
    ON di.icd_code = d.icd_code
    AND di.icd_version = d.icd_version
  WHERE d.icd_code IN ('5849', 'N179') -- AKI codes
),

icu_with_aki AS (
  SELECT
    t.stay_id,
    t.temp_category,
    t.temperature,
    CASE WHEN a.hadm_id IS NOT NULL THEN 1 ELSE 0 END AS aki
  FROM icu_temp_first24 t
  JOIN `physionet-data.mimiciv_3_1_icu.icustays` icu
    ON t.stay_id = icu.stay_id
  LEFT JOIN aki_patients a
    ON icu.hadm_id = a.hadm_id
)

SELECT
  temp_category,
  COUNT(*) AS n_measurements,
  COUNT(DISTINCT stay_id) AS n_patients,
  AVG(temperature) AS mean_temp,
  APPROX_QUANTILES(temperature, 2)[OFFSET(1)] AS median_temp,
  APPROX_QUANTILES(temperature, 4)[OFFSET(1)] AS q1_temp,
  APPROX_QUANTILES(temperature, 4)[OFFSET(3)] AS q3_temp,
  (APPROX_QUANTILES(temperature, 4)[OFFSET(3)] - APPROX_QUANTILES(temperature, 4)[OFFSET(1)]) AS iqr_temp,
  AVG(CAST(aki AS FLOAT64)) AS aki_rate
FROM icu_with_aki
WHERE temp_category IS NOT NULL
GROUP BY temp_category
ORDER BY
  CASE temp_category
    WHEN '<36.0' THEN 1
    WHEN '36.0–37.9' THEN 2
    WHEN '≥38.0' THEN 3
  END;