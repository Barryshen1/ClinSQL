SELECT AVG(c.valuenum) AS avg_map
FROM `physionet-data.mimiciv_3_1_icu.chartevents` c
JOIN `physionet-data.mimiciv_3_1_icu.d_items` di ON c.itemid = di.itemid
JOIN `physionet-data.mimiciv_3_1_icu.icustays` i ON c.stay_id = i.stay_id
JOIN `physionet-data.mimiciv_3_1_hosp.patients` p ON i.subject_id = p.subject_id
WHERE p.gender = 'F'
  AND p.anchor_age BETWEEN 73 AND 83
  AND (i.first_careunit LIKE '%Step Down%' OR i.first_careunit LIKE '%IMC%' OR i.last_careunit LIKE '%Step Down%' OR i.last_careunit LIKE '%IMC%')
  AND di.label LIKE '%MAP%';