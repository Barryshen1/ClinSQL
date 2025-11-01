WITH heart_rate_itemid AS (
  SELECT itemid
  FROM `physionet-data.mimiciv_3_1_icu.d_items`
  WHERE label LIKE '%Heart Rate%'
),
patient_selection AS (
  SELECT p.subject_id
  FROM `physionet-data.mimiciv_3_1_hosp.patients` p
  WHERE p.gender = 'F' AND p.anchor_age BETWEEN 38 AND 48
),
first_hr AS (
  SELECT ce.valuenum, 
         ROW_NUMBER() OVER (PARTITION BY ce.stay_id ORDER BY ce.charttime) as hr_seq
  FROM patient_selection p
  JOIN `physionet-data.mimiciv_3_1_icu.icustays` icu ON p.subject_id = icu.subject_id
  JOIN `physionet-data.mimiciv_3_1_icu.chartevents` ce ON icu.stay_id = ce.stay_id
  JOIN heart_rate_itemid hri ON ce.itemid = hri.itemid
)
SELECT MIN(valuenum) as min_first_hr
FROM first_hr
WHERE hr_seq = 1;