SELECT STDDEV(ce.valuenum) AS sbp_std_dev
FROM `physionet-data.mimiciv_3_1_icu.icustays` ie
INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` p 
  ON ie.subject_id = p.subject_id
INNER JOIN `physionet-data.mimiciv_3_1_icu.chartevents` ce 
  ON ie.stay_id = ce.stay_id
  AND ie.subject_id = ce.subject_id
  AND ie.hadm_id = ce.hadm_id
WHERE 
  p.gender = 'M'
  AND p.anchor_age BETWEEN 76 AND 86
  AND ce.itemid IN (220179, 225309, 220050)  -- SBP item IDs
  AND ce.valuenum IS NOT NULL  -- Ensure numeric values
  AND ce.charttime >= ie.intime
  AND ce.charttime <= DATETIME_ADD(ie.intime, INTERVAL 24 HOUR);