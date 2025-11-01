WITH cohort AS (
  SELECT 
    i.subject_id, 
    i.stay_id, 
    i.intime
  FROM `physionet-data.mimiciv_3_1_icu.icustays` i
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON i.subject_id = p.subject_id
  WHERE 
    p.gender = 'F'
    AND p.anchor_age BETWEEN 67 AND 77
),
hr_data AS (
  SELECT 
    c.stay_id,
    AVG(ch.valuenum) AS avg_hr
  FROM cohort c
  INNER JOIN `physionet-data.mimiciv_3_1_icu.chartevents` ch
    ON c.subject_id = ch.subject_id
    AND c.stay_id = ch.stay_id
  WHERE 
    ch.itemid = 220045  -- Heart Rate
    AND ch.valuenum IS NOT NULL
    AND ch.charttime >= c.intime
    AND ch.charttime <= TIMESTAMP_ADD(c.intime, INTERVAL 24 HOUR)
  GROUP BY c.stay_id
)
SELECT 
  100.0 * AVG(IF(avg_hr <= 110, 1, 0)) AS percentile
FROM hr_data;