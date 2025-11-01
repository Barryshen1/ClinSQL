WITH per_stay AS (
  SELECT
    icu.subject_id,
    icu.hadm_id,
    icu.stay_id,
    MIN(
      CASE
        -- Fahrenheit already
        WHEN LOWER(c.valueuom) LIKE '%degf%' OR LOWER(c.valueuom) LIKE '%fahrenheit%' THEN c.valuenum
        -- Celsius: convert to Fahrenheit
        WHEN LOWER(c.valueuom) LIKE '%degc%' OR LOWER(c.valueuom) LIKE '%celsius%' THEN c.valuenum * 9.0/5.0 + 32.0
        ELSE NULL
      END
    ) AS min_temp_f
  FROM `physionet-data.mimiciv_3_1_icu.icustays` AS icu
  JOIN `physionet-data.mimiciv_3_1_icu.chartevents` AS c
    ON c.subject_id = icu.subject_id
   AND c.hadm_id = icu.hadm_id
   AND c.stay_id = icu.stay_id
  JOIN `physionet-data.mimiciv_3_1_icu.d_items` AS di
    ON c.itemid = di.itemid
  WHERE c.charttime BETWEEN icu.intime AND icu.outtime
    AND LOWER(di.label) LIKE '%temperature%'
  GROUP BY icu.subject_id, icu.hadm_id, icu.stay_id
)
SELECT (quantiles)[OFFSET(1)] AS median_min_temperature_f
FROM (
  SELECT APPROX_QUANTILES(min_temp_f, 2) AS quantiles
  FROM per_stay ps
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` AS p
    ON ps.subject_id = p.subject_id
  WHERE p.gender = 'Male'
    AND p.anchor_age BETWEEN 74 AND 84
    AND ps.min_temp_f IS NOT NULL
) t;