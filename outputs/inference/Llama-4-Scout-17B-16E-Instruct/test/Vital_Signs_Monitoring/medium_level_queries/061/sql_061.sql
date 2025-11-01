WITH 
eligible_patients AS (
  SELECT p.subject_id, p.anchor_age, p.gender
  FROM `physionet-data.mimiciv_3_1_hosp`.patients p
  WHERE p.gender = 'M' AND p.anchor_age BETWEEN 38 AND 48
),

icu_stays AS (
  SELECT i.subject_id, i.stay_id, i.hadm_id
  FROM `physionet-data.mimiciv_3_1_icu`.icustays i
  JOIN eligible_patients p ON i.subject_id = p.subject_id
),

avg_map AS (
  SELECT 
    AVG(CAST(ce.valuenum AS FLOAT64)) AS avg_map
  FROM `physionet-data.mimiciv_3_1_icu`.chartevents ce
  JOIN icu_stays is_ ON ce.stay_id = is_.stay_id
  WHERE ce.itemid = 220050 AND ce.valuenum IS NOT NULL
)

SELECT 
  COUNTIF(avg_map <= 60) * 1.0 / COUNT(*) AS proportion
FROM avg_map;