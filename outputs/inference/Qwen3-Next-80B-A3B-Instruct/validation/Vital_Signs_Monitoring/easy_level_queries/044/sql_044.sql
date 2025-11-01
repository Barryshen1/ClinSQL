WITH max_map_per_hadm AS (
  SELECT 
    c.hadm_id,
    MAX(c.valuenum) AS max_map
  FROM 
    physionet-data.mimiciv_3_1_icu.chartevents c
  INNER JOIN 
    physionet-data.mimiciv_3_1_icu.d_items d 
    ON c.itemid = d.itemid
  INNER JOIN 
    physionet-data.mimiciv_3_1_hosp.admissions a 
    ON c.hadm_id = a.hadm_id
  INNER JOIN 
    physionet-data.mimiciv_3_1_hosp.patients p 
    ON a.subject_id = p.subject_id
  WHERE 
    d.label = 'MAP'
    AND p.gender = 'F'
    AND p.anchor_age BETWEEN 82 AND 92
    AND c.valuenum IS NOT NULL
  GROUP BY 
    c.hadm_id
)
SELECT 
  APPROX_QUANTILES(max_map, 1)[OFFSET(1)] AS median_max_map
FROM 
  max_map_per_hadm;