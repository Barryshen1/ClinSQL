WITH map_itemids AS (
  -- Identify MAP itemids from d_items
  SELECT itemid
  FROM `physionet-data.mimiciv_3_1_icu.d_items`
  WHERE LOWER(label) LIKE '%mean arterial pressure%'
     OR LOWER(label) LIKE '%map%'
),
icu_males_52_62 AS (
  -- Get ICU stays for males aged 52-62
  SELECT
    icu.subject_id,
    icu.hadm_id,
    icu.stay_id,
    icu.intime
  FROM `physionet-data.mimiciv_3_1_icu.icustays` icu
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` pat
    ON icu.subject_id = pat.subject_id
  WHERE pat.gender = 'M'
    AND pat.anchor_age BETWEEN 52 AND 62
),
first_map AS (
  -- For each ICU stay, get the first MAP value at or after ICU admission
  SELECT
    icu.subject_id,
    icu.hadm_id,
    icu.stay_id,
    MIN(ce.charttime) AS first_map_time
  FROM icu_males_52_62 icu
  JOIN `physionet-data.mimiciv_3_1_icu.chartevents` ce
    ON icu.stay_id = ce.stay_id
  JOIN map_itemids mi
    ON ce.itemid = mi.itemid
  WHERE ce.valuenum IS NOT NULL
    AND ce.charttime >= icu.intime
  GROUP BY icu.subject_id, icu.hadm_id, icu.stay_id
),
first_map_values AS (
  -- Get the MAP value corresponding to the first MAP time for each stay
  SELECT
    icu.subject_id,
    icu.hadm_id,
    icu.stay_id,
    ce.valuenum AS first_map_value
  FROM icu_males_52_62 icu
  JOIN first_map fm
    ON icu.stay_id = fm.stay_id
  JOIN `physionet-data.mimiciv_3_1_icu.chartevents` ce
    ON icu.stay_id = ce.stay_id
    AND ce.charttime = fm.first_map_time
  JOIN map_itemids mi
    ON ce.itemid = mi.itemid
  WHERE ce.valuenum IS NOT NULL
)
SELECT
  PERCENTILE_CONT(first_map_value, 0.25) OVER() AS map_25th_percentile,
  PERCENTILE_CONT(first_map_value, 0.75) OVER() AS map_75th_percentile
FROM first_map_values;