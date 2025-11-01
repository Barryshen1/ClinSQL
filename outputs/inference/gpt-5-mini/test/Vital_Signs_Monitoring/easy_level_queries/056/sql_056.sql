WITH temp_candidates AS (
  SELECT
    ce.subject_id,
    ce.hadm_id,
    ce.stay_id,
    ce.charttime,
    ce.valuenum,
    ce.valueuom,
    di.label AS item_label,
    di.abbreviation AS item_abbrev,
    di.unitname AS item_unit,
    icu.intime,
    -- Convert to Fahrenheit when unit indicates Celsius; otherwise assume Fahrenheit
    CASE
      WHEN ce.valuenum IS NULL THEN NULL
      WHEN LOWER(COALESCE(ce.valueuom, '')) LIKE '%c%' THEN ce.valuenum * 9.0/5.0 + 32.0
      WHEN LOWER(COALESCE(ce.valueuom, '')) LIKE '%f%' THEN ce.valuenum
      WHEN LOWER(COALESCE(di.unitname, '')) LIKE '%c%' THEN ce.valuenum * 9.0/5.0 + 32.0
      WHEN LOWER(COALESCE(di.unitname, '')) LIKE '%f%' THEN ce.valuenum
      ELSE ce.valuenum
    END AS temp_f
  FROM `physionet-data.mimiciv_3_1_icu.chartevents` ce
  JOIN `physionet-data.mimiciv_3_1_icu.d_items` di
    ON ce.itemid = di.itemid
  JOIN `physionet-data.mimiciv_3_1_icu.icustays` icu
    ON ce.stay_id = icu.stay_id
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON ce.subject_id = p.subject_id
  WHERE p.gender = 'M'
    AND p.anchor_age BETWEEN 46 AND 56
    AND ce.charttime BETWEEN icu.intime AND TIMESTAMP_ADD(icu.intime, INTERVAL 24 HOUR)
    AND ce.valuenum IS NOT NULL
    -- Identify temperature-related items conservatively by label/abbreviation/category
    AND (
      LOWER(COALESCE(di.label, '')) LIKE '%temp%'
      OR LOWER(COALESCE(di.label, '')) LIKE '%temperature%'
      OR LOWER(COALESCE(di.abbreviation, '')) LIKE '%temp%'
      OR LOWER(COALESCE(di.category, '')) LIKE '%vital%'
    )
),

-- Keep only plausible Fahrenheit values
temp_filtered AS (
  SELECT *
  FROM temp_candidates
  WHERE temp_f IS NOT NULL
    AND temp_f BETWEEN 85.0 AND 110.0
),

-- Compute per-stay median temperature (first 24h) using APPROX_QUANTILES
per_stay_medians AS (
  SELECT
    subject_id,
    hadm_id,
    stay_id,
    APPROX_QUANTILES(temp_f, 100)[OFFSET(50)] AS median_temp_f
  FROM temp_filtered
  GROUP BY subject_id, hadm_id, stay_id
)

-- Final: median of the per-stay medians
SELECT
  COUNT(*) AS n_stays_included,
  APPROX_QUANTILES(median_temp_f, 100)[OFFSET(50)] AS median_temperature_f_across_stays
FROM per_stay_medians;