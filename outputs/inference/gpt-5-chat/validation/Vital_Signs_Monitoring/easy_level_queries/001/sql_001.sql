WITH map_itemids AS (
  SELECT itemid
  FROM `physionet-data.mimiciv_3_1_icu.d_items`
  WHERE LOWER(label) LIKE '%mean arterial pressure%'
),
first_map_per_stay AS (
  SELECT
    icu.subject_id,
    icu.hadm_id,
    icu.stay_id,
    MIN_BY(ce.valuenum, ce.charttime) AS first_map_value
  FROM `physionet-data.mimiciv_3_1_icu.icustays` icu
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` pat
    ON icu.subject_id = pat.subject_id
  JOIN `physionet-data.mimiciv_3_1_icu.chartevents` ce
    ON icu.stay_id = ce.stay_id
  JOIN map_itemids mi
    ON ce.itemid = mi.itemid
  WHERE pat.gender = 'M'
    AND pat.anchor_age BETWEEN 52 AND 62
    AND ce.valuenum IS NOT NULL
  GROUP BY icu.subject_id, icu.hadm_id, icu.stay_id
)
SELECT
  PERCENTILE_CONT(first_map_value, 0.25) OVER () AS map_iqr_25,
  PERCENTILE_CONT(first_map_value, 0.75) OVER () AS map_iqr_75
FROM first_map_per_stay
LIMIT 1;