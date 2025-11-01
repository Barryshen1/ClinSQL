WITH 
female_patients AS (
  SELECT p.subject_id, p.anchor_year - p.anchor_age AS year_of_birth, icu.hadm_id, icu.stay_id
  FROM `physionet-data.mimiciv_3_1_hosp.patients` p
  JOIN `physionet-data.mimiciv_3_1_icu.icustays` icu ON p.subject_id = icu.subject_id
  WHERE p.gender = 'F' AND p.anchor_age BETWEEN 41 AND 51
),

map_measurements AS (
  SELECT ce.subject_id, ce.stay_id, ce.charttime, ce.valuenum AS map_value
  FROM `physionet-data.mimiciv_3_1_icu.chartevents` ce
  WHERE ce.itemid = 220052  
),

categorized_map AS (
  SELECT subject_id, stay_id, 
         CASE 
           WHEN map_value < 65 THEN '<65'
           WHEN map_value BETWEEN 65 AND 74 THEN '65-74'
           WHEN map_value BETWEEN 75 AND 84 THEN '75-84'
           ELSE '>=85'
         END AS map_category
  FROM map_measurements
),

stroke_patients AS (
  SELECT DISTINCT d.subject_id
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
  JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` dicd ON d.icd_code = dicd.icd_code AND d.icd_version = dicd.icd_version
  WHERE dicd.long_title LIKE '%stroke%' AND d.icd_version = 10  
)

SELECT 
  cm.map_category,
  COUNT(DISTINCT cm.subject_id) AS patient_count,
  COUNT(DISTINCT CASE WHEN sp.subject_id IS NOT NULL THEN cm.subject_id END) / COUNT(DISTINCT cm.subject_id) AS stroke_rate
FROM categorized_map cm
LEFT JOIN stroke_patients sp ON cm.subject_id = sp.subject_id
JOIN female_patients fp ON cm.subject_id = fp.subject_id AND cm.stay_id = fp.stay_id
GROUP BY cm.map_category
ORDER BY cm.map_category;