WITH filtered_stays AS (
  SELECT 
    i.stay_id,
    i.subject_id,
    i.intime,
    i.outtime
  FROM 
    `physionet-data.mimiciv_3_1_icu.icustays` i
  INNER JOIN 
    `physionet-data.mimiciv_3_1_hosp.patients` p
  ON 
    i.subject_id = p.subject_id
  WHERE 
    p.gender = 'F'
    AND p.anchor_age BETWEEN 71 AND 81
),
dbp_measurements AS (
  SELECT 
    ce.stay_id,
    ce.valuenum AS dbp
  FROM 
    `physionet-data.mimiciv_3_1_icu.chartevents` ce
  INNER JOIN 
    filtered_stays fs
  ON 
    ce.subject_id = fs.subject_id
    AND ce.stay_id = fs.stay_id
  WHERE 
    ce.itemid = 220061
    AND ce.valuenum IS NOT NULL
    AND ce.charttime BETWEEN fs.intime AND fs.outtime
),
per_stay_max_dbp AS (
  SELECT 
    stay_id,
    MAX(dbp) AS max_dbp
  FROM 
    dbp_measurements
  GROUP BY 
    stay_id
  HAVING 
    max_dbp IS NOT NULL
)
SELECT 
  PERCENTILE_CONT(max_dbp, 0.5) OVER() AS median_max_dbp
FROM 
  per_stay_max_dbp;