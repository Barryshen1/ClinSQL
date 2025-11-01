WITH 
hr_itemid AS (
  SELECT itemid 
  FROM `physionet-data.mimiciv_3_1_icu.d_items` 
  WHERE label = 'Heart Rate'
),
avg_hr AS (
  SELECT 
    ie.stay_id,
    AVG(ce.valuenum) AS avg_hr
  FROM 
    `physionet-data.mimiciv_3_1_icu.icustays` ie
  INNER JOIN 
    `physionet-data.mimiciv_3_1_hosp.patients` p ON ie.subject_id = p.subject_id
  INNER JOIN 
    `physionet-data.mimiciv_3_1_icu.chartevents` ce ON ie.stay_id = ce.stay_id
  WHERE 
    p.gender = 'F' 
    AND p.anchor_age BETWEEN 67 AND 77
    AND ce.itemid = (SELECT itemid FROM hr_itemid)
    AND ce.charttime BETWEEN ie.intime AND TIMESTAMP_ADD(ie.intime, INTERVAL 24 HOUR)
  GROUP BY 
    ie.stay_id
)
SELECT 
  COUNTIF(avg_hr.avg_hr <= 110) / COUNT(*) * 100 AS percentile
FROM 
  avg_hr;