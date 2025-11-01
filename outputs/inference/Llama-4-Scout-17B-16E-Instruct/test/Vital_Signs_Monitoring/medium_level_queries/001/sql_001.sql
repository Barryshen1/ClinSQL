WITH 
sbp_itemid AS (
  SELECT itemid 
  FROM `physionet-data.mimiciv_3_1_icu.d_items` 
  WHERE label = 'Systolic Blood Pressure'
),

patients_of_interest AS (
  SELECT p.subject_id, p.anchor_age, p.gender
  FROM `physionet-data.mimiciv_3_1_hosp.patients` p
  WHERE p.gender = 'F' AND p.anchor_age BETWEEN 45 AND 55
),

icu_stays AS (
  SELECT i.subject_id, i.hadm_id, i.stay_id, i.intime
  FROM `physionet-data.mimiciv_3_1_icu.icustays` i
  JOIN patients_of_interest p ON i.subject_id = p.subject_id
),

sbp_measurements AS (
  SELECT 
    c.subject_id, 
    c.stay_id,
    c.valuenum AS sbp_value
  FROM `physionet-data.mimiciv_3_1_icu.chartevents` c
  JOIN sbp_itemid s ON c.itemid = s.itemid
  JOIN icu_stays i ON c.subject_id = i.subject_id AND c.stay_id = i.stay_id
  WHERE c.charttime BETWEEN i.intime AND TIMESTAMP_ADD(i.intime, INTERVAL 24 HOUR)
),

avg_sbp_per_stay AS (
  SELECT 
    stay_id,
    AVG(sbp_value) AS avg_sbp
  FROM sbp_measurements
  GROUP BY stay_id
),

categorized AS (
  SELECT 
    stay_id,
    CASE 
      WHEN avg_sbp < 140 THEN '<140'
      WHEN avg_sbp BETWEEN 140 AND 159 THEN '140–159'
      ELSE '≥160'
    END AS sbp_category
  FROM avg_sbp_per_stay
)

SELECT 
  sbp_category, 
  COUNT(DISTINCT stay_id) AS patient_count
FROM categorized
GROUP BY sbp_category;