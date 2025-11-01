WITH map_items AS (
  -- Identify itemids that correspond to mean arterial pressure (MAP)
  SELECT itemid, label
  FROM `physionet-data.mimiciv_3_1_icu.d_items`
  WHERE LOWER(label) LIKE '%mean arterial%'
     OR LOWER(label) LIKE '%map%'
),

first_map_per_stay AS (
  -- For each ICU stay, find the first MAP measurement at or after ICU intime
  SELECT
    ce.subject_id,
    ce.hadm_id,
    ce.stay_id,
    ce.charttime,
    ce.valuenum AS map_val,
    ROW_NUMBER() OVER (PARTITION BY ce.stay_id ORDER BY ce.charttime ASC) AS rn
  FROM `physionet-data.mimiciv_3_1_icu.chartevents` ce
  JOIN map_items mi
    ON ce.itemid = mi.itemid
  JOIN `physionet-data.mimiciv_3_1_icu.icustays` icu
    ON ce.subject_id = icu.subject_id
   AND ce.stay_id = icu.stay_id
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON ce.subject_id = p.subject_id
  WHERE ce.charttime >= icu.intime
    AND ce.valuenum IS NOT NULL
    AND ce.valuenum > 0
    AND ce.valuenum < 300
    AND p.gender = 'M'
    AND p.anchor_age BETWEEN 52 AND 62
)

SELECT
  q.quantiles[OFFSET(1)] AS q1_map,
  q.quantiles[OFFSET(3)] AS q3_map,
  SAFE_CAST(q.quantiles[OFFSET(3)] - q.quantiles[OFFSET(1)] AS FLOAT64) AS iqr_map,
  q.quantiles[OFFSET(2)] AS median_map,
  cnt.n_stays
FROM (
  -- single-row: array of quantiles (min, Q1, median, Q3, max)
  SELECT APPROX_QUANTILES(map_val, 4) AS quantiles
  FROM first_map_per_stay
  WHERE rn = 1
) AS q
CROSS JOIN (
  -- single-row: count of first MAP per stay used in quantiles
  SELECT COUNT(1) AS n_stays
  FROM first_map_per_stay
  WHERE rn = 1
) AS cnt;