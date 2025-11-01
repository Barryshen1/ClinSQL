WITH eligible_stays AS (
  SELECT 
    i.stay_id,
    i.subject_id,
    i.intime,
    p.gender,
    p.anchor_age
  FROM 
    `physionet-data.mimiciv_3_1_icu.icustays` i
  INNER JOIN 
    `physionet-data.mimiciv_3_1_hosp.patients` p
  ON 
    i.subject_id = p.subject_id
  WHERE 
    p.gender = 'F'
    AND p.anchor_age BETWEEN 38 AND 48
),
bp_measurements AS (
  SELECT 
    es.stay_id,
    es.intime,
    c.charttime,
    c.itemid,
    c.valuenum
  FROM 
    eligible_stays es
  INNER JOIN 
    `physionet-data.mimiciv_3_1_icu.chartevents` c
  ON 
    es.subject_id = c.subject_id
    AND es.stay_id = c.stay_id
  WHERE 
    c.itemid IN (220045, 220179)  -- Systolic BP: Arterial systolic, NBP Sys
    AND c.valueuom = 'mmHg'
    AND c.valuenum IS NOT NULL
    AND c.charttime >= es.intime 
    AND c.charttime <= TIMESTAMP_ADD(es.intime, INTERVAL 48 HOUR)
),
stay_averages AS (
  SELECT 
    stay_id,
    AVG(valuenum) AS avg_sbp
  FROM 
    bp_measurements
  GROUP BY 
    stay_id
)
SELECT 
  130 AS target_sbp,
  PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY avg_sbp) AS median_sbp,  -- For context
  -- Percentile rank of 130: position in sorted avg_sbp distribution
  (COUNT(*) FILTER (WHERE avg_sbp <= 130) * 1.0 / COUNT(*)) * 100 AS percentile_for_130
FROM 
  stay_averages
  CROSS JOIN (SELECT 130 AS ref_value)  -- Dummy cross join for scalar computation
HAVING 
  COUNT(*) > 0;  -- Ensure data exists;