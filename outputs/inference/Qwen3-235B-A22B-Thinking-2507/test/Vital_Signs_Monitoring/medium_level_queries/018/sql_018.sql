WITH cohort_stays AS (
  SELECT 
    i.stay_id,
    i.intime
  FROM `physionet-data.mimiciv_3_1_icu.icustays` i
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON i.subject_id = p.subject_id
  WHERE p.gender = 'F'
    AND (p.anchor_age + (EXTRACT(YEAR FROM i.intime) - p.anchor_year)) BETWEEN 75 AND 85
),
systolic_bp AS (
  SELECT 
    c.stay_id,
    c.valuenum AS sbp
  FROM `physionet-data.mimiciv_3_1_icu.chartevents` c
  INNER JOIN cohort_stays s
    ON c.stay_id = s.stay_id
  WHERE c.charttime BETWEEN s.intime AND DATETIME_ADD(s.intime, INTERVAL 48 HOUR)
    AND c.itemid IN (220050, 220179, 220180, 220181, 225309, 225310, 227243, 224167)
    AND c.valuenum IS NOT NULL
),
stay_means AS (
  SELECT 
    stay_id,
    AVG(sbp) AS mean_sbp
  FROM systolic_bp
  GROUP BY stay_id
  HAVING COUNT(sbp) > 0
)
SELECT 
  (COUNT(CASE WHEN mean_sbp <= 140 THEN 1 END) * 100.0) / COUNT(*) AS percentile_rank
FROM stay_means;