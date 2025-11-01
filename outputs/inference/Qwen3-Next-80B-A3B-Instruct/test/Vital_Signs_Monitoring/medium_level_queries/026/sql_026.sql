WITH eligible_patients AS (
  SELECT 
    p.subject_id,
    p.anchor_age,
    p.gender,
    i.stay_id,
    i.intime
  FROM 
    physionet-data.mimiciv_3_1_hosp.patients p
  INNER JOIN 
    physionet-data.mimiciv_3_1_icu.icustays i
    ON p.subject_id = i.subject_id
  WHERE 
    p.gender = 'M'
    AND p.anchor_age BETWEEN 68 AND 78
),
respiratory_rate_measurements AS (
  SELECT 
    ep.stay_id,
    ce.valuenum AS rr_value
  FROM 
    eligible_patients ep
  INNER JOIN 
    physionet-data.mimiciv_3_1_icu.chartevents ce
    ON ep.stay_id = ce.stay_id
  INNER JOIN 
    physionet-data.mimiciv_3_1_icu.d_items di
    ON ce.itemid = di.itemid
  WHERE 
    di.label IN ('Respiratory Rate', 'RR')
    AND ce.valuenum IS NOT NULL
    AND ce.valuenum BETWEEN 5 AND 60  -- reasonable range
    AND ce.charttime >= ep.intime
    AND ce.charttime < ep.intime + INTERVAL '48' HOUR
),
per_stay_avg_rr AS (
  SELECT 
    stay_id,
    AVG(rr_value) AS avg_rr
  FROM 
    respiratory_rate_measurements
  GROUP BY 
    stay_id
)
SELECT 
  (SUM(CASE WHEN avg_rr <= 12 THEN 1 ELSE 0 END) * 100.0 / COUNT(*)) AS percentile
FROM 
  per_stay_avg_rr;