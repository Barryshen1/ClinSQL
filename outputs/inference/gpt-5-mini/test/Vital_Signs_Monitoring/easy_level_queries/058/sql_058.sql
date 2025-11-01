WITH temp_items AS (
  SELECT itemid
  FROM `physionet-data.mimiciv_3_1_icu.d_items`
  WHERE LOWER(label) LIKE '%temp%' OR LOWER(label) LIKE '%temperature%'
),

-- per-stay temperature measurements converted to Fahrenheit
stay_temps AS (
  SELECT
    icu.stay_id,
    ce.charttime,
    ce.valuenum AS raw_val,
    ce.valueuom AS raw_uom,
    CASE
      WHEN ce.valuenum IS NULL THEN NULL
      WHEN LOWER(IFNULL(ce.valueuom, '')) LIKE '%f%' THEN ce.valuenum
      WHEN LOWER(IFNULL(ce.valueuom, '')) LIKE '%c%' THEN ce.valuenum * 9.0/5.0 + 32.0
      WHEN ce.valuenum <= 45 THEN ce.valuenum * 9.0/5.0 + 32.0  -- likely Celsius
      ELSE ce.valuenum  -- likely Fahrenheit
    END AS temp_f
  FROM `physionet-data.mimiciv_3_1_icu.icustays` icu
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON icu.subject_id = p.subject_id
  JOIN `physionet-data.mimiciv_3_1_icu.chartevents` ce
    ON ce.stay_id = icu.stay_id
  JOIN temp_items di
    ON ce.itemid = di.itemid
  WHERE
    p.gender = 'M'
    AND p.anchor_age BETWEEN 74 AND 84
    AND ce.valuenum IS NOT NULL
),

-- per-stay minimum temperature (°F)
per_stay_min AS (
  SELECT
    stay_id,
    MIN(temp_f) AS min_temp_f
  FROM stay_temps
  WHERE temp_f IS NOT NULL
  GROUP BY stay_id
),

-- ordered list to compute exact median
ordered AS (
  SELECT
    min_temp_f,
    ROW_NUMBER() OVER (ORDER BY min_temp_f) AS rn,
    COUNT(*) OVER () AS cnt
  FROM per_stay_min
)

SELECT
  CASE
    WHEN cnt = 0 THEN NULL
    WHEN MOD(cnt, 2) = 1 THEN
      (SELECT min_temp_f FROM ordered WHERE rn = (cnt + 1) / 2)
    ELSE
      (
        (SELECT min_temp_f FROM ordered WHERE rn = cnt / 2)
        + (SELECT min_temp_f FROM ordered WHERE rn = cnt / 2 + 1)
      ) / 2.0
  END AS median_min_temperature_f
FROM ordered
LIMIT 1;