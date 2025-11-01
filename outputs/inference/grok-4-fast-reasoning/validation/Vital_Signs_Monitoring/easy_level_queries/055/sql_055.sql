WITH cohort AS (
  SELECT 
    i.stay_id, 
    i.subject_id, 
    i.intime, 
    p.gender,
    p.anchor_age + EXTRACT(YEAR FROM i.intime) - 2008 AS age
  FROM 
    `physionet-data.mimiciv_3_1_icu.icustays` i
  INNER JOIN 
    `physionet-data.mimiciv_3_1_hosp.patients` p
  ON 
    i.subject_id = p.subject_id
  WHERE 
    p.gender = 'M'
    AND i.first_careunit LIKE '%Stepdown%'
    AND p.anchor_age + EXTRACT(YEAR FROM i.intime) - 2008 BETWEEN 76 AND 86
)
SELECT 
  STDDEV(ce.valuenum) AS sd_sbp
FROM 
  cohort c
INNER JOIN 
  `physionet-data.mimiciv_3_1_icu.chartevents` ce
ON 
  c.stay_id = ce.stay_id
WHERE 
  ce.itemid IN (220045, 220179)
  AND ce.valuenum IS NOT NULL
  AND ce.charttime >= c.intime
  AND ce.charttime < DATETIME_ADD(c.intime, INTERVAL 24 HOUR);