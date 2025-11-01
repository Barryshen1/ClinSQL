WITH temp_measurements AS (
  SELECT
    i.subject_id,
    i.hadm_id,
    i.stay_id,
    ce.charttime,
    ce.valuenum,
    LOWER(COALESCE(ce.valueuom, di.unitname, '')) AS unit_normalized,
    di.label AS item_label,
    -- convert Fahrenheit to Celsius when unit indicates F, otherwise treat as Celsius
    CASE
      WHEN LOWER(COALESCE(ce.valueuom, di.unitname, '')) LIKE '%f%' THEN (ce.valuenum - 32) * 5.0/9.0
      ELSE ce.valuenum
    END AS temp_c
  FROM `physionet-data.mimiciv_3_1_icu.icustays` i
  JOIN `physionet-data.mimiciv_3_1_icu.chartevents` ce
    ON ce.stay_id = i.stay_id
  LEFT JOIN `physionet-data.mimiciv_3_1_icu.d_items` di
    ON ce.itemid = di.itemid
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON i.subject_id = p.subject_id
  WHERE
    -- patient filters
    p.gender = 'M'
    AND p.anchor_age BETWEEN 67 AND 77
    -- time window: first 24 hours of ICU stay (inclusive)
    AND ce.charttime IS NOT NULL
    AND ce.charttime BETWEEN i.intime AND TIMESTAMP_ADD(i.intime, INTERVAL 24 HOUR)
    -- numeric measurement required
    AND ce.valuenum IS NOT NULL
    -- identify likely temperature items by label/abbrev or unit
    AND (
         LOWER(COALESCE(di.label, '')) LIKE '%temp%'
      OR LOWER(COALESCE(di.abbreviation, '')) LIKE '%temp%'
      OR LOWER(COALESCE(di.label, '')) LIKE '%temperature%'
      OR LOWER(COALESCE(ce.valueuom, '')) LIKE '%f%'
      OR LOWER(COALESCE(ce.valueuom, '')) LIKE '%c%'
      OR LOWER(COALESCE(di.unitname, '')) LIKE '%cel%'
      OR LOWER(COALESCE(di.unitname, '')) LIKE '%f%'
    )
    -- keep plausible human temps after conversion
    AND (
      CASE
        WHEN LOWER(COALESCE(ce.valueuom, di.unitname, '')) LIKE '%f%' THEN (ce.valuenum - 32) * 5.0/9.0
        ELSE ce.valuenum
      END BETWEEN 25 AND 45
    )
),

per_stay_avg AS (
  -- compute per-stay average temperature (C) over the first 24 hours
  SELECT
    stay_id,
    subject_id,
    hadm_id,
    AVG(temp_c) AS avg_temp_c,
    COUNT(*) AS n_measurements
  FROM temp_measurements
  GROUP BY stay_id, subject_id, hadm_id
)

-- final percentile calculation: proportion of stays with per-stay avg <= 36.0°C
SELECT
  COUNTIF(avg_temp_c <= 36.0) AS stays_le_36,
  COUNT(*) AS total_stays,
  100.0 * COUNTIF(avg_temp_c <= 36.0) / COUNT(*) AS percentile_le_36
FROM per_stay_avg;