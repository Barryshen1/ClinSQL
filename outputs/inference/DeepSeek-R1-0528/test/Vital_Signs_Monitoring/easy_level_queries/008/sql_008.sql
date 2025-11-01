SELECT MAX(ce.valuenum) AS max_resp_rate
FROM `physionet-data.mimiciv_3_1_hosp.patients` p
INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a
  ON p.subject_id = a.subject_id
INNER JOIN `physionet-data.mimiciv_3_1_icu.icustays` i
  ON a.hadm_id = i.hadm_id
INNER JOIN `physionet-data.mimiciv_3_1_icu.chartevents` ce
  ON i.stay_id = ce.stay_id
    AND i.subject_id = ce.subject_id
    AND i.hadm_id = ce.hadm_id
WHERE 
  p.gender = 'M'
  AND (p.anchor_age + EXTRACT(YEAR FROM a.admittime) - p.anchor_year) BETWEEN 52 AND 62
  AND ce.itemid IN (220210, 224690, 224689)  -- Respiratory rate item IDs
  AND ce.valuenum IS NOT NULL
  AND ce.valuenum > 0  -- Exclude invalid values
  AND TIMESTAMP_DIFF(ce.charttime, i.intime, HOUR) >= 24  -- ICU day 2 or later;