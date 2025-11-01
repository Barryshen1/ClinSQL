WITH cohort_stays AS (
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
    p.gender = 'F'
    AND p.anchor_age >= 75
    AND p.anchor_age <= 85
),
bp_measurements AS (
  SELECT 
    cs.stay_id, 
    c.valuenum, 
    c.charttime
  FROM 
    cohort_stays cs
  INNER JOIN 
    `physionet-data.mimiciv_3_1_icu.chartevents` c
  ON 
    cs.stay_id = c.stay_id
  WHERE 
    c.itemid IN (51, 220045, 220179)
    AND c.valuenum > 0
    AND c.valuenum < 400
    AND c.charttime >= cs.intime
    AND c.charttime < TIMESTAMP_ADD(cs.intime, INTERVAL 48 HOUR)
)
SELECT 
  COUNTIF(mean_sbp <= 140) * 100.0 / COUNT(*) AS percentile
FROM (
  SELECT 
    AVG(valuenum) AS mean_sbp
  FROM 
    bp_measurements
  GROUP BY 
    stay_id
  HAVING 
    COUNT(*) > 0
);