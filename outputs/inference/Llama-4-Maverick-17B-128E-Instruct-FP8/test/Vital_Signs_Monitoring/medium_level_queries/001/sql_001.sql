WITH patient_filter AS (
  SELECT subject_id
  FROM `physionet-data.mimiciv_3_1_hosp.patients`
  WHERE gender = 'F' AND anchor_age BETWEEN 45 AND 55
),
sbp_measurements AS (
  SELECT 
    ie.stay_id,
    ce.valuenum AS sbp
  FROM `physionet-data.mimiciv_3_1_icu.icustays` ie
  INNER JOIN `physionet-data.mimiciv_3_1_icu.chartevents` ce ON ie.stay_id = ce.stay_id
  INNER JOIN `physionet-data.mimiciv_3_1_icu.d_items` di ON ce.itemid = di.itemid
  WHERE di.label LIKE '%Systolic Blood Pressure%' 
    AND ce.charttime BETWEEN ie.intime AND TIMESTAMP_ADD(ie.intime, INTERVAL 24 HOUR)
    AND ie.subject_id IN (SELECT subject_id FROM patient_filter)
),
average_sbp AS (
  SELECT 
    stay_id,
    AVG(sbp) AS avg_sbp
  FROM sbp_measurements
  GROUP BY stay_id
),
categorized_sbp AS (
  SELECT 
    ie.subject_id,
    CASE 
      WHEN avg_sbp < 140 THEN '<140'
      WHEN avg_sbp BETWEEN 140 AND 159 THEN '140-159'
      ELSE '>=160'
    END AS sbp_category
  FROM average_sbp
  INNER JOIN `physionet-data.mimiciv_3_1_icu.icustays` ie ON average_sbp.stay_id = ie.stay_id
),
unique_patients AS (
  SELECT DISTINCT 
    subject_id,
    sbp_category
  FROM categorized_sbp
)
SELECT 
  sbp_category,
  COUNT(subject_id) AS count_unique_patients
FROM unique_patients
GROUP BY sbp_category;