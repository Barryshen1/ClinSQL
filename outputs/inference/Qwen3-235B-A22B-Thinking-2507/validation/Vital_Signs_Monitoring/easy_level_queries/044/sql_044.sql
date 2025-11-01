WITH filtered_admissions AS (
  SELECT 
    a.hadm_id,
    a.subject_id
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON a.subject_id = p.subject_id
  WHERE p.gender = 'F'
    AND (p.anchor_age + (EXTRACT(YEAR FROM a.admittime) - p.anchor_year)) BETWEEN 82 AND 92
),
map_values AS (
  SELECT 
    fa.hadm_id,
    ce.valuenum AS map_value
  FROM filtered_admissions fa
  INNER JOIN `physionet-data.mimiciv_3_1_icu.icustays` icu
    ON fa.hadm_id = icu.hadm_id AND fa.subject_id = icu.subject_id
  INNER JOIN `physionet-data.mimiciv_3_1_icu.chartevents` ce
    ON icu.stay_id = ce.stay_id
  WHERE ce.itemid = 220052
    AND ce.valuenum IS NOT NULL
),
max_map_per_admission AS (
  SELECT 
    hadm_id,
    MAX(map_value) AS max_map
  FROM map_values
  GROUP BY hadm_id
)
SELECT 
  PERCENTILE_CONT(max_map, 0.5) OVER () AS median_max_map
FROM max_map_per_admission
LIMIT 1;