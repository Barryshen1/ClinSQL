WITH eligible_patients AS (
  SELECT 
    p.subject_id,
    p.anchor_age,
    i.stay_id,
    i.intime,
    i.outtime
  FROM 
    physionet-data.mimiciv_3_1_hosp.patients p
  INNER JOIN 
    physionet-data.mimiciv_3_1_icu.icustays i
    ON p.subject_id = i.subject_id
  WHERE 
    p.gender = 'F' 
    AND p.anchor_age BETWEEN 87 AND 97
),
sbp_chartevents AS (
  SELECT 
    ce.stay_id,
    ce.valuenum
  FROM 
    physionet-data.mimiciv_3_1_icu.chartevents ce
  INNER JOIN 
    physionet-data.mimiciv_3_1_icu.d_items di
    ON ce.itemid = di.itemid
  INNER JOIN 
    eligible_patients ep
    ON ce.stay_id = ep.stay_id
  WHERE 
    LOWER(di.label) LIKE '%systolic%'
    AND ce.valuenum IS NOT NULL
    AND ce.valuenum > 0
    AND ce.valuenum < 300  -- reasonable range
    AND ce.charttime >= ep.intime
    AND ce.charttime < ep.intime + INTERVAL '24' HOUR
),
avg_sbp_per_stay AS (
  SELECT 
    stay_id,
    AVG(valuenum) AS avg_sbp_24h
  FROM 
    sbp_chartevents
  GROUP BY 
    stay_id
  HAVING 
    COUNT(*) >= 1  -- at least one measurement
)
SELECT 
  (SUM(CASE WHEN avg_sbp_24h <= 150 THEN 1 ELSE 0 END) * 100.0 / COUNT(*)) AS percentile_150
FROM 
  avg_sbp_per_stay;