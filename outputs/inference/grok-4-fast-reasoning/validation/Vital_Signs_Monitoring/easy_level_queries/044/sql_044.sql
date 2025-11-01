WITH max_maps AS (
  SELECT 
    ce.hadm_id,
    MAX(ce.valuenum) AS max_map
  FROM 
    `physionet-data.mimiciv_3_1_icu.chartevents` ce
  JOIN 
    `physionet-data.mimiciv_3_1_hosp.patients` p ON ce.subject_id = p.subject_id
  JOIN 
    `physionet-data.mimiciv_3_1_hosp.admissions` a ON ce.hadm_id = a.hadm_id
  WHERE 
    p.gender = 'F'
    AND p.anchor_age BETWEEN 82 AND 92
    AND ce.itemid = 220052
    AND ce.valuenum IS NOT NULL
    AND ce.valuenum > 0
  GROUP BY 
    ce.hadm_id
)
SELECT 
  PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY max_map) AS median_max_map
FROM 
  max_maps;