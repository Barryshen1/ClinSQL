WITH temp_measurements AS (
  SELECT
    ce.subject_id,
    ce.hadm_id,
    ce.stay_id,
    ce.charttime,
    ce.valuenum,
    ce.valueuom,
    di.label AS item_label
  FROM `physionet-data.mimiciv_3_1_icu.chartevents` AS ce
  JOIN `physionet-data.mimiciv_3_1_icu.icustays` AS icu
    ON ce.stay_id = icu.stay_id
  JOIN `physionet-data.mimiciv_3_1_hosp.d_labitems` AS di
    ON ce.itemid = di.itemid
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` AS p
    ON icu.subject_id = p.subject_id
  WHERE
    LOWER(di.label) LIKE '%temperature%'
    AND ce.charttime >= icu.intime
    AND ce.charttime <= TIMESTAMP_ADD(icu.intime, INTERVAL 24 HOUR)
    AND p.gender = 'M'
    AND p.anchor_age BETWEEN 46 AND 56
    AND ce.valuenum IS NOT NULL
    AND ce.valueuom IS NOT NULL
),
temp_fahrenheit AS (
  SELECT
    CASE
      WHEN UPPER(CE.valueuom) IN ('C', 'CELSIUS') THEN CE.valuenum * 9.0/5.0 + 32
      WHEN UPPER(CE.valueuom) IN ('F', 'FAHRENHEIT') THEN CE.valuenum
      ELSE NULL
    END AS temp_f
  FROM temp_measurements AS CE
  WHERE
    CASE
      WHEN UPPER(CE.valueuom) IN ('C', 'CELSIUS') THEN CE.valuenum * 9.0/5.0 + 32
      WHEN UPPER(CE.valueuom) IN ('F', 'FAHRENHEIT') THEN CE.valuenum
      ELSE NULL
    END IS NOT NULL
)
SELECT
  APPROX_QUANTILES(temp_f, 100)[OFFSET(50)] AS median_temperature_f
FROM temp_fahrenheit
WHERE temp_f IS NOT NULL;