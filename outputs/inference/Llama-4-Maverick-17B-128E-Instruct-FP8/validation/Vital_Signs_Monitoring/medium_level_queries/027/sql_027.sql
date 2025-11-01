WITH 
heart_rate_itemid AS (
  SELECT itemid
  FROM `physionet-data.mimiciv_3_1_icu.d_items`
  WHERE label = 'Heart Rate' AND linksto = 'chartevents'
),
average_heart_rate AS (
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
    AND p.anchor_age BETWEEN 80 AND 90
    AND ce.itemid = (SELECT itemid FROM heart_rate_itemid)
  GROUP BY 
    ie.stay_id
)
SELECT 
  100 * (COUNTIF(avg_hr <= 110) / COUNT(*))
FROM 
  average_heart_rate;