WITH filtered_admissions AS (
  SELECT a.hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` p 
    ON a.subject_id = p.subject_id
  WHERE p.gender = 'F'
    AND (p.anchor_age + EXTRACT(YEAR FROM a.admittime) - p.anchor_year) BETWEEN 82 AND 92
),
max_map_per_hadm AS (
  SELECT 
    c.hadm_id,
    MAX(c.valuenum) AS max_map
  FROM `physionet-data.mimiciv_3_1_icu.chartevents` c
  JOIN filtered_admissions fa 
    ON c.hadm_id = fa.hadm_id
  WHERE c.itemid = 456
    AND c.valuenum IS NOT NULL
  GROUP BY c.hadm_id
)
SELECT 
  PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY max_map) AS median_max_map
FROM max_map_per_hadm;