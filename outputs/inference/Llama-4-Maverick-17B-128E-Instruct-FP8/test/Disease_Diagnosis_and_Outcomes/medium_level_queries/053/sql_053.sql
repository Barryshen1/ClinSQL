WITH 
filtered_patients AS (
  SELECT a.hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` p ON a.subject_id = p.subject_id
  WHERE p.gender = 'M' AND p.anchor_age BETWEEN 39 AND 49
),
pneumonia_patients AS (
  SELECT DISTINCT d.hadm_id, 
         CASE 
           WHEN di.long_title LIKE '%Aspiration%' THEN 'Aspiration'
           ELSE 'Community-acquired'
         END AS pneumonia_type
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
  JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` di ON d.icd_code = di.icd_code AND d.icd_version = di.icd_version
  JOIN filtered_patients fp ON d.hadm_id = fp.hadm_id
  WHERE di.long_title LIKE '%Pneumonia%'
),
patient_stay_info AS (
  SELECT a.hadm_id, 
         DATETIME_DIFF(a.dischtime, a.admittime, DAY) AS los,
         CASE 
           WHEN i.intime <= DATETIME_ADD(a.admittime, INTERVAL 1 DAY) THEN 1
           ELSE 0
         END AS icu_day1
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  LEFT JOIN `physionet-data.mimiciv_3_1_icu.icustays` i ON a.hadm_id = i.hadm_id
  WHERE a.hadm_id IN (SELECT hadm_id FROM pneumonia_patients)
),
mortality_info AS (
  SELECT hadm_id, hospital_expire_flag
  FROM `physionet-data.mimiciv_3_1_hosp.admissions`
  WHERE hadm_id IN (SELECT hadm_id FROM pneumonia_patients)
),
comorbidity_count AS (
  SELECT hadm_id, COUNT(DISTINCT icd_code) AS comorbidity_cnt
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd`
  WHERE hadm_id IN (SELECT hadm_id FROM pneumonia_patients)
  GROUP BY hadm_id
)
SELECT 
  pp.pneumonia_type,
  CASE 
    WHEN psi.los BETWEEN 1 AND 3 THEN '1-3'
    WHEN psi.los BETWEEN 4 AND 7 THEN '4-7'
    ELSE '>=8'
  END AS los_category,
  psi.icu_day1,
  COUNT(*) AS total_patients,
  SUM(mi.hospital_expire_flag) AS total_deaths,
  (SUM(mi.hospital_expire_flag) / COUNT(*)) * 100 AS mortality_rate,
  AVG(cc.comorbidity_cnt) AS avg_comorbidity_cnt
FROM pneumonia_patients pp
JOIN patient_stay_info psi ON pp.hadm_id = psi.hadm_id
JOIN mortality_info mi ON pp.hadm_id = mi.hadm_id
JOIN comorbidity_count cc ON pp.hadm_id = cc.hadm_id
GROUP BY pp.pneumonia_type, los_category, psi.icu_day1
ORDER BY pp.pneumonia_type, los_category, psi.icu_day1;