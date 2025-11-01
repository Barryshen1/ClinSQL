WITH eligible_stays AS (
  SELECT 
    i.subject_id,
    i.stay_id,
    i.intime
  FROM 
    `physionet-data.mimiciv_3_1_hosp.patients` p
  INNER JOIN 
    `physionet-data.mimiciv_3_1_icu.icustays` i
  ON 
    p.subject_id = i.subject_id
  WHERE 
    p.anchor_age BETWEEN 39 AND 49
    AND p.gender = 'M'
    AND (i.first_careunit LIKE '%ICU%' OR i.last_careunit LIKE '%ICU%')
)
SELECT 
  MIN(ce.valuenum) AS min_respiratory_rate
FROM 
  eligible_stays es
INNER JOIN 
  `physionet-data.mimiciv_3_1_icu.chartevents` ce
ON 
  es.subject_id = ce.subject_id
  AND es.stay_id = ce.stay_id
WHERE 
  ce.itemid = 618
  AND ce.valuenum IS NOT NULL
  AND ce.valuenum > 0
  AND ce.charttime >= es.intime
  AND ce.charttime <= DATETIME_ADD(es.intime, INTERVAL 24 HOUR);