WITH eligible_patients AS (
  SELECT 
    p.subject_id,
    i.stay_id,
    i.intime
  FROM 
    `physionet-data.mimiciv_3_1_icu.icustays` i
  INNER JOIN 
    `physionet-data.mimiciv_3_1_hosp.patients` p
  ON 
    i.subject_id = p.subject_id
  WHERE 
    p.gender = 'F'
    AND p.anchor_age BETWEEN 89 AND 99
    AND i.subject_id !=  -- Exclude the specific patient (94yo female; replace with actual ID if known)
      (SELECT subject_id FROM `physionet-data.mimiciv_3_1_hosp.patients` 
       WHERE gender = 'F' AND anchor_age = 94 LIMIT 1)  -- Placeholder; adjust if exact ID available
)
SELECT 
  AVG(ce.valuenum) AS avg_map_first_24h
FROM 
  eligible_patients ep
INNER JOIN 
  `physionet-data.mimiciv_3_1_icu.chartevents` ce
ON 
  ep.subject_id = ce.subject_id 
  AND ep.stay_id = ce.stay_id
WHERE 
  ce.itemid = 220052  -- MAP
  AND ce.valuenum IS NOT NULL
  AND ce.charttime >= ep.intime
  AND ce.charttime <= TIMESTAMP_ADD(ep.intime, INTERVAL 24 HOUR);