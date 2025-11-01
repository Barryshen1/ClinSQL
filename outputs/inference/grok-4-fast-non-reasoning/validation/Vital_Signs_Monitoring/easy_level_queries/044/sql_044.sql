WITH max_map_per_stay AS (
  SELECT 
    c.subject_id,
    c.hadm_id,
    c.stay_id,
    MAX(c.valuenum) AS max_map_stay
  FROM 
    `physionet-data.mimiciv_3_1_icu.chartevents` c
  INNER JOIN 
    `physionet-data.mimiciv_3_1_hosp.admissions` a
  ON 
    c.hadm_id = a.hadm_id
    AND c.charttime >= a.admittime 
    AND c.charttime < a.dischtime
  INNER JOIN 
    `physionet-data.mimiciv_3_1_hosp.patients` p
  ON 
    c.subject_id = p.subject_id
  WHERE 
    p.gender = 'F'
    AND p.anchor_age BETWEEN 82 AND 92
    AND c.itemid = 220052
    AND c.valuenum IS NOT NULL
  GROUP BY 
    c.subject_id, c.hadm_id, c.stay_id
),
max_map_per_hadm AS (
  SELECT 
    subject_id,
    hadm_id,
    MAX(max_map_stay) AS max_map_hadm
  FROM 
    max_map_per_stay
  GROUP BY 
    subject_id, hadm_id
)
SELECT 
  APPROX_QUANTILES(max_map_hadm, 2)[OFFSET(1)] AS median_max_map
FROM 
  max_map_per_hadm;