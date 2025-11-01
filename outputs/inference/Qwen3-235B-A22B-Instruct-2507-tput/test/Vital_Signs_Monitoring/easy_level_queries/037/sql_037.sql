SELECT 
  AVG(ce.valuenum) AS average_map
FROM 
  `physionet-data.mimiciv_3_1_hosp`.patients p
JOIN 
  `physionet-data.mimiciv_3_1_icu`.icustays icu
  ON p.subject_id = icu.subject_id
JOIN 
  `physionet-data.mimiciv_3_1_icu`.chartevents ce
  ON icu.stay_id = ce.stay_id
JOIN 
  `physionet-data.mimiciv_3_1_icu`.d_items di
  ON ce.itemid = di.itemid
WHERE 
  p.gender = 'F'
  AND p.anchor_age BETWEEN 89 AND 99
  AND LOWER(di.label) = 'mean blood pressure'
  AND ce.charttime >= icu.intime
  AND ce.charttime <= DATETIME_ADD(icu.intime, INTERVAL 24 HOUR)
  AND ce.valuenum IS NOT NULL;