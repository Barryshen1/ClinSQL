WITH eligible_patients AS (
  SELECT subject_id
  FROM `physionet-data.mimiciv_3_1_hosp.patients`
  WHERE gender = 'F' 
    AND anchor_age BETWEEN 37 AND 47
),
eligible_stays AS (
  SELECT stay_id
  FROM `physionet-data.mimiciv_3_1_icu.icustays` cs
  INNER JOIN eligible_patients ep 
    ON cs.subject_id = ep.subject_id
),
mean_temps AS (
  SELECT 
    ce.stay_id, 
    AVG(ce.valuenum) AS mean_temp
  FROM `physionet-data.mimiciv_3_1_icu.chartevents` ce
  INNER JOIN `physionet-data.mimiciv_3_1_icu.d_items` di 
    ON ce.itemid = di.itemid 
    AND di.category = 'Temperature'
  INNER JOIN eligible_stays es 
    ON ce.stay_id = es.stay_id
  WHERE ce.valuenum IS NOT NULL
  GROUP BY ce.stay_id
)
SELECT 
  APPROX_QUANTILES(mean_temp, 4)[OFFSET(3)] AS p75_mean_temp
FROM mean_temps;