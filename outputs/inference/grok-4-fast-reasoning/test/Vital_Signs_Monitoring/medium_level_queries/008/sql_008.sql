WITH cohort AS (
  SELECT 
    i.subject_id, 
    i.stay_id, 
    i.intime, 
    p.gender, 
    p.anchor_age,
    p.anchor_age + EXTRACT(YEAR FROM i.intime) - 2008 AS age
  FROM 
    `physionet-data.mimiciv_3_1_icu.icustays` i
  INNER JOIN 
    `physionet-data.mimiciv_3_1_hosp.patients` p
  ON 
    i.subject_id = p.subject_id
  WHERE 
    p.gender = 'M'
    AND (p.anchor_age + EXTRACT(YEAR FROM i.intime) - 2008) BETWEEN 39 AND 49
),
maps AS (
  SELECT 
    c.stay_id, 
    AVG(ce.valuenum) AS avg_map
  FROM 
    cohort c
  INNER JOIN 
    `physionet-data.mimiciv_3_1_icu.chartevents` ce
  ON 
    ce.stay_id = c.stay_id
  WHERE 
    ce.itemid = 220052
    AND ce.charttime >= c.intime
    AND ce.charttime <= TIMESTAMP_ADD(c.intime, INTERVAL 1 DAY)
    AND ce.valuenum IS NOT NULL
  GROUP BY 
    c.stay_id
)
SELECT 
  SAFE_DIVIDE(COUNTIF(avg_map <= 75), COUNT(*)) * 100 AS percentile
FROM 
  maps;