WITH temp_events AS (
  SELECT
    ce.subject_id,
    ce.hadm_id,
    ce.stay_id,
    ce.charttime,
    ce.valuenum,
    LOWER(coalesce(ce.valueuom, di.unitname)) AS unit,
    -- convert to Fahrenheit if unit indicates Celsius; otherwise assume Fahrenheit
    CASE
      WHEN ce.valuenum IS NULL THEN NULL
      WHEN LOWER(coalesce(ce.valueuom, di.unitname)) LIKE '%c%' THEN ce.valuenum * 9.0 / 5.0 + 32.0
      ELSE ce.valuenum
    END AS temp_f
  FROM
    `physionet-data.mimiciv_3_1_icu.chartevents` ce
  JOIN
    `physionet-data.mimiciv_3_1_icu.d_items` di
    ON ce.itemid = di.itemid
  JOIN
    `physionet-data.mimiciv_3_1_icu.icustays` icu
    ON ce.subject_id = icu.subject_id
    AND ce.stay_id = icu.stay_id
  JOIN
    `physionet-data.mimiciv_3_1_hosp.patients` p
    ON ce.subject_id = p.subject_id
  WHERE
    -- identify temperature-related items by label/abbreviation
    (
      LOWER(di.label) LIKE '%temp%'
      OR LOWER(di.label) LIKE '%temperature%'
      OR LOWER(coalesce(di.abbreviation, '')) LIKE '%temp%'
      OR LOWER(coalesce(di.abbreviation, '')) LIKE '%temperature%'
    )
    -- female and age between 86 and 96 (inclusive)
    AND p.gender = 'F'
    AND p.anchor_age BETWEEN 86 AND 96
    -- measurement must have a charttime and be within first 24 hours of ICU stay
    AND ce.charttime IS NOT NULL
    AND ce.charttime BETWEEN icu.intime AND TIMESTAMP_ADD(icu.intime, INTERVAL 24 HOUR)
    -- numeric value present
    AND ce.valuenum IS NOT NULL
)
SELECT
  -- approximate 75th percentile (in °F)
  APPROX_QUANTILES(temp_f, 100)[OFFSET(75)] AS temperature_75th_percentile_f,
  -- context counts
  COUNT(*) AS n_measurements,
  COUNT(DISTINCT subject_id) AS n_patients
FROM
  temp_events
WHERE
  -- restrict to plausible body temperatures in Fahrenheit to reduce impact of bad data
  temp_f BETWEEN 85 AND 110;