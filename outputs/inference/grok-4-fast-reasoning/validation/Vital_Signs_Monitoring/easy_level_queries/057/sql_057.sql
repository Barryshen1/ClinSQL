WITH qualifying_stays AS (
  SELECT 
    c.stay_id,
    MAX(c.valuenum) AS max_rr
  FROM 
    `physionet-data.mimiciv_3_1_hosp.patients` p
  INNER JOIN 
    `physionet-data.mimiciv_3_1_icu.icustays` i
  ON p.subject_id = i.subject_id
  INNER JOIN 
    `physionet-data.mimiciv_3_1_icu.chartevents` c
  ON i.subject_id = c.subject_id 
    AND i.stay_id = c.stay_id
    AND c.charttime >= i.intime 
    AND c.charttime <= i.outtime
    AND c.itemid IN (618, 220210)
    AND c.valuenum IS NOT NULL
  WHERE 
    p.gender = 'M'
    AND p.anchor_age BETWEEN 35 AND 45
  GROUP BY 
    c.stay_id
  HAVING 
    max_rr IS NOT NULL
)
SELECT 
  MIN(max_rr) AS min_of_max_respiratory_rate
FROM 
  qualifying_stays;