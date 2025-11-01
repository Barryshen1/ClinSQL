WITH temp_itemids AS (
  -- pick itemids that look like temperature measurements
  SELECT itemid
  FROM `physionet-data.mimiciv_3_1_icu.d_items`
  WHERE LOWER(label) LIKE '%temp%'
     OR LOWER(label) LIKE '%temperature%'
     OR LOWER(abbreviation) LIKE '%temp%'
),

first_temps AS (
  -- for each icu stay, get the first temperature measurement within first 24 hours of ICU admission
  SELECT
    i.subject_id,
    i.hadm_id,
    i.stay_id,
    ce.charttime,
    -- convert F -> C if unit indicates Fahrenheit; otherwise assume Celsius
    CASE
      WHEN ce.valuenum IS NULL THEN NULL
      WHEN LOWER(COALESCE(ce.valueuom, '')) LIKE '%f%' THEN (ce.valuenum - 32) * 5.0/9.0
      ELSE ce.valuenum
    END AS temp_c
  FROM `physionet-data.mimiciv_3_1_icu.icustays` i
  JOIN `physionet-data.mimiciv_3_1_icu.chartevents` ce
    ON ce.stay_id = i.stay_id
  JOIN temp_itemids di
    ON ce.itemid = di.itemid
  WHERE i.hadm_id IS NOT NULL
    AND ce.charttime BETWEEN i.intime AND TIMESTAMP_ADD(i.intime, INTERVAL 24 HOUR)
    AND ce.valuenum IS NOT NULL
),

first_temps_per_stay AS (
  -- select the earliest valid temperature per stay, filter for plausible temps
  SELECT
    ft.subject_id,
    ft.hadm_id,
    ft.stay_id,
    ft.charttime,
    ft.temp_c
  FROM (
    SELECT
      ft.*,
      ROW_NUMBER() OVER (PARTITION BY ft.stay_id ORDER BY ft.charttime ASC) AS rn
    FROM first_temps ft
  ) ft
  WHERE rn = 1
    AND ft.temp_c BETWEEN 30.0 AND 45.0   -- plausible clinical range in Celsius
),

cohort AS (
  -- restrict to female patients age 62-72 inclusive
  SELECT
    fts.*,
    p.gender,
    p.anchor_age
  FROM first_temps_per_stay fts
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON p.subject_id = fts.subject_id
  WHERE LOWER(p.gender) = 'f'
    AND p.anchor_age BETWEEN 62 AND 72
),

aki_flags AS (
  -- admissions with an AKI diagnosis (based on diagnosis description)
  SELECT DISTINCT
    d.hadm_id,
    TRUE AS has_aki
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
  LEFT JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` dd
    ON d.icd_code = dd.icd_code
   AND d.icd_version = dd.icd_version
  WHERE LOWER(COALESCE(dd.long_title, '')) LIKE '%acute kidney%'
     OR LOWER(COALESCE(dd.long_title, '')) LIKE '%acute renal%'
),

-- aggregate per temperature category, compute quantiles array and AKI counts
quantiles_per_cat AS (
  SELECT
    temp_cat,
    COUNT(1) AS n_stays,
    ROUND(AVG(temp_c), 2) AS mean_temp_c,
    APPROX_QUANTILES(temp_c, 100) AS quantiles,  -- array of percentiles 0..100
    SUM(CASE WHEN COALESCE(ak.has_aki, FALSE) THEN 1 ELSE 0 END) AS aki_count
  FROM (
    SELECT
      c.*,
      CASE
        WHEN temp_c < 36.0 THEN '<36.0'
        WHEN temp_c >= 38.0 THEN '>=38.0'
        ELSE '36.0-37.9'
      END AS temp_cat
    FROM cohort c
  ) c
  LEFT JOIN aki_flags ak
    ON ak.hadm_id = c.hadm_id
  GROUP BY temp_cat
)

SELECT
  qpc.temp_cat,
  qpc.n_stays,
  qpc.mean_temp_c,
  ROUND(qpc.quantiles[OFFSET(50)], 2) AS median_temp_c,
  ROUND(qpc.quantiles[OFFSET(25)], 2) AS q1_temp_c,
  ROUND(qpc.quantiles[OFFSET(75)], 2) AS q3_temp_c,
  ROUND(qpc.quantiles[OFFSET(75)] - qpc.quantiles[OFFSET(25)], 2) AS iqr_temp_c,
  ROUND(SAFE_DIVIDE(qpc.aki_count, qpc.n_stays) * 100, 1) AS aki_rate_percent
FROM quantiles_per_cat qpc
ORDER BY
  CASE qpc.temp_cat
    WHEN '<36.0' THEN 1
    WHEN '36.0-37.9' THEN 2
    WHEN '>=38.0' THEN 3
    ELSE 4
  END;