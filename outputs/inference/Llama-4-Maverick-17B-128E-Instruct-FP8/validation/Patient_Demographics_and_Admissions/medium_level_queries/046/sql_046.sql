WITH patient_age AS (
  SELECT p.subject_id, p.gender, a.hadm_id, 
         p.anchor_age + EXTRACT(YEAR FROM a.admittime) - p.anchor_year AS age_at_admission
  FROM `physionet-data.mimiciv_3_1_hosp.patients` p
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a ON p.subject_id = a.subject_id
),
icustay_details AS (
  SELECT a.hadm_id, 
         icu.stay_id, 
         icu.los,
         CASE 
           WHEN a.discharge_location = 'HOME' THEN 'home'
           WHEN a.discharge_location IN ('SKILLED NURSING FACILITY', 'REHAB FACILITY', 'NURSING HOME') THEN 'facility'
           WHEN a.hospital_expire_flag = 1 THEN 'in-hospital death'
           ELSE 'other'
         END AS discharge_category
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  INNER JOIN `physionet-data.mimiciv_3_1_icu.icustays` icu ON a.hadm_id = icu.hadm_id
),
filtered_data AS (
  SELECT hadm_id, stay_id, los, discharge_category
  FROM icustay_details
  WHERE hadm_id IN (
    SELECT hadm_id
    FROM patient_age
    WHERE gender = 'F' AND age_at_admission BETWEEN 87 AND 97
  )
  AND discharge_category IN ('home', 'facility', 'in-hospital death')
)
SELECT 
  discharge_category,
  COUNT(*) AS n,
  AVG(los) AS mean_los,
  STDDEV(los) AS std_los,
  SUM(CASE WHEN los < 10 THEN 1 ELSE 0 END) / COUNT(*) * 100 AS percent_los_lt_10
FROM filtered_data
GROUP BY discharge_category;