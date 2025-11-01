WITH stays AS (
  SELECT 
    i.stay_id,
    i.subject_id,
    i.intime,
    p.gender,
    p.anchor_age,
    p.anchor_year,
    EXTRACT(YEAR FROM i.intime) - p.anchor_year + p.anchor_age AS age
  FROM `physionet-data.mimiciv_3_1_icu.icustays` i
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` p 
    ON i.subject_id = p.subject_id
  WHERE p.gender = 'F'
    AND EXTRACT(YEAR FROM i.intime) - p.anchor_year + p.anchor_age BETWEEN 38 AND 48
),
sbp_measurements AS (
  SELECT 
    c.stay_id,
    c.valuenum,
    c.charttime
  FROM `physionet-data.mimiciv_3_1_icu.chartevents` c
  INNER JOIN stays s 
    ON c.stay_id = s.stay_id
  WHERE c.itemid IN (220045, 220179)
    AND c.valuenum IS NOT NULL
    AND c.valuenum > 0
    AND c.charttime >= s.intime
    AND c.charttime <= DATETIME_ADD(s.intime, INTERVAL 1 DAY)
),
avg_sbp AS (
  SELECT 
    stay_id,
    AVG(valuenum) AS avg_sbp
  FROM sbp_measurements
  GROUP BY stay_id
)
SELECT 
  COUNTIF(a.avg_sbp <= 120) * 100.0 / COUNT(*) AS percentile
FROM avg_sbp a;