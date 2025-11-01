WITH cohort AS (
  SELECT 
    p.subject_id, 
    i.stay_id, 
    i.intime
  FROM 
    `physionet-data.mimiciv_3_1_hosp.patients` p
  INNER JOIN 
    `physionet-data.mimiciv_3_1_icu.icustays` i
  ON 
    p.subject_id = i.subject_id
  WHERE 
    p.gender = 'M'
    AND p.anchor_age BETWEEN 55 AND 65
),
first_map AS (
  SELECT 
    c.stay_id, 
    ce.valuenum
  FROM 
    cohort c
  INNER JOIN 
    `physionet-data.mimiciv_3_1_icu.chartevents` ce
  ON 
    c.stay_id = ce.stay_id
  WHERE 
    ce.itemid = 220052
    AND ce.charttime >= c.intime
    AND ce.valuenum IS NOT NULL
  QUALIFY 
    ROW_NUMBER() OVER (PARTITION BY c.stay_id ORDER BY ce.charttime ASC) = 1
)
SELECT 
  STDDEV_SAMP(valuenum) AS sd_first_map
FROM 
  first_map;