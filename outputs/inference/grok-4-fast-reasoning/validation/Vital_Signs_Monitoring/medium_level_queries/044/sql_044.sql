WITH qualifying_stays AS (
  SELECT 
    ie.stay_id, 
    p.gender, 
    p.anchor_age, 
    ie.intime
  FROM `physionet-data.mimiciv_3_1_icu`.icustays ie
  INNER JOIN `physionet-data.mimiciv_3_1_hosp`.patients p
    ON ie.subject_id = p.subject_id
  WHERE p.gender = 'M'
    AND p.anchor_age BETWEEN 81 AND 91
),
systolic_bp AS (
  SELECT 
    ce.stay_id, 
    ce.valuenum
  FROM `physionet-data.mimiciv_3_1_icu`.chartevents ce
  INNER JOIN qualifying_stays qs 
    ON ce.stay_id = qs.stay_id
  WHERE ce.itemid IN (220045, 220179)
    AND ce.valuenum IS NOT NULL
    AND ce.valuenum > 0
    AND ce.valuenum < 300
    AND ce.charttime >= qs.intime
    AND ce.charttime <= TIMESTAMP_ADD(qs.intime, INTERVAL 48 HOUR)
)
SELECT 
  COUNTIF(avg_sbp <= 150) * 100.0 / COUNT(*) AS percentile
FROM (
  SELECT 
    stay_id, 
    AVG(valuenum) AS avg_sbp
  FROM systolic_bp
  GROUP BY stay_id
) avgs;