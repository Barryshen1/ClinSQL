WITH ami_patients AS (
  SELECT p.subject_id, a.hadm_id, p.anchor_age, a.admittime, a.dischtime, a.hospital_expire_flag, a.discharge_location,
         DATETIME_DIFF(a.dischtime, a.admittime, DAY) AS los
  FROM `physionet-data.mimiciv_3_1_hosp.patients` p
  JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a ON p.subject_id = a.subject_id
  JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d ON a.hadm_id = d.hadm_id
  JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` dicd ON d.icd_code = dicd.icd_code AND d.icd_version = dicd.icd_version
  WHERE p.gender = 'M' AND p.anchor_age BETWEEN 69 AND 79
  AND dicd.long_title LIKE '%Myocardial infarction%'
  AND a.hadm_id NOT IN (SELECT hadm_id FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` WHERE icd_code LIKE '785.5%')  
  AND a.hadm_id NOT IN (SELECT hadm_id FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` WHERE icd_code LIKE '518.81%')  
),
categorized_los AS (
  SELECT hadm_id, 
         CASE 
           WHEN los BETWEEN 1 AND 3 THEN '1-3'
           WHEN los BETWEEN 4 AND 7 THEN '4-7'
           ELSE '>=8'
         END AS los_category,
         hospital_expire_flag, discharge_location, los
  FROM ami_patients
)
SELECT 
  los_category,
  COUNT(*) AS total_patients,
  SUM(hospital_expire_flag) / COUNT(*) * 100 AS mortality_percent,
  APPROX_QUANTILES(los, 100)[OFFSET(50)] AS median_los,
  COUNTIF(discharge_location = 'HOME') / COUNT(*) * 100 AS discharge_home_percent,
  COUNTIF(discharge_location = 'DEAD/EXPIRED') / COUNT(*) * 100 AS discharge_dead_percent
FROM categorized_los
GROUP BY los_category
ORDER BY los_category;