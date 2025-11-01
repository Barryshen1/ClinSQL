WITH troponin_t_itemid AS (
  SELECT itemid
  FROM `physionet-data.mimiciv_3_1_hosp.d_labitems`
  WHERE label LIKE '%Troponin T%' 
  -- Removed the condition on loinc_code as it's not recognized and might not be necessary
),
patient_data AS (
  SELECT p.subject_id, p.anchor_age, a.hadm_id, a.hospital_expire_flag
  FROM `physionet-data.mimiciv_3_1_hosp.patients` p
  JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a ON p.subject_id = a.subject_id
  WHERE p.gender = 'M' AND p.anchor_age BETWEEN 87 AND 97
  AND a.admission_type = 'EMERGENCY'  -- Assuming ACS suspicion is more likely in emergency admissions
),
troponin_t_data AS (
  SELECT pd.hadm_id, le.valuenum, le.charttime,
         ROW_NUMBER() OVER (PARTITION BY pd.hadm_id ORDER BY le.charttime) AS troponin_t_seq
  FROM patient_data pd
  JOIN `physionet-data.mimiciv_3_1_hosp.labevents` le ON pd.hadm_id = le.hadm_id
  WHERE le.itemid IN (SELECT itemid FROM troponin_t_itemid)
),
first_troponin_t AS (
  SELECT hadm_id, valuenum
  FROM troponin_t_data
  WHERE troponin_t_seq = 1
),
categorized_troponin_t AS (
  SELECT hadm_id,
         CASE
           WHEN valuenum < 0.01 THEN 'Normal/Minimal'  
           WHEN valuenum < 0.1 THEN 'Borderline'  
           ELSE 'Elevated'
         END AS troponin_t_category
  FROM first_troponin_t
)
SELECT 
  ctt.troponin_t_category,
  COUNT(*) AS count_patients,
  COUNT(*) * 100.0 / SUM(COUNT(*)) OVER () AS percentage,
  SUM(pd.hospital_expire_flag) * 100.0 / COUNT(*) AS in_hospital_mortality_rate
FROM categorized_troponin_t ctt
JOIN patient_data pd ON ctt.hadm_id = pd.hadm_id
GROUP BY ctt.troponin_t_category
ORDER BY ctt.troponin_t_category;