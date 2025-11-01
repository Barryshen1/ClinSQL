SELECT 
  AVG(ce.valuenum) AS average_map
FROM 
  `physionet-data.mimiciv_3_1_icu.icustays` icu
INNER JOIN 
  `physionet-data.mimiciv_3_1_hosp.patients` p 
  ON icu.subject_id = p.subject_id
INNER JOIN 
  `physionet-data.mimiciv_3_1_icu.chartevents` ce 
  ON icu.stay_id = ce.stay_id
INNER JOIN 
  `physionet-data.mimiciv_3_1_icu.d_items` di 
  ON ce.itemid = di.itemid
WHERE 
  p.gender = 'F'
  AND (EXTRACT(YEAR FROM icu.intime) - p.anchor_year + p.anchor_age) BETWEEN 89 AND 99
  AND ce.charttime BETWEEN icu.intime AND DATETIME_ADD(icu.intime, INTERVAL 24 HOUR)
  AND di.label = 'Arterial Blood Pressure mean'
  AND ce.valuenum IS NOT NULL;