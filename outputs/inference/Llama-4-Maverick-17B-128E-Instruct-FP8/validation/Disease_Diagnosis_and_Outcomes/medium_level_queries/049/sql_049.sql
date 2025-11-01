WITH 
-- Step 1: Filter patients based on age and gender, and get hadm_id
patient_filter AS (
  SELECT DISTINCT p.subject_id, a.hadm_id, p.anchor_age
  FROM `physionet-data.mimiciv_3_1_hosp.patients` p
  JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a ON p.subject_id = a.subject_id
  WHERE p.gender = 'M' AND p.anchor_age BETWEEN 51 AND 61
),

-- Step 2: Identify STEMI/NSTEMI patients
stem_nstem AS (
  SELECT p.hadm_id,
         MAX(CASE WHEN d.long_title LIKE '%STEMI%' THEN 1 ELSE 0 END) AS stemi_flag,
         MAX(CASE WHEN d.long_title LIKE '%NSTEMI%' THEN 1 ELSE 0 END) AS nstemi_flag
  FROM patient_filter p
  JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` di ON p.hadm_id = di.hadm_id
  JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` d ON di.icd_code = d.icd_code AND di.icd_version = d.icd_version
  WHERE di.icd_version = 10 AND (d.long_title LIKE '%STEMI%' OR d.long_title LIKE '%NSTEMI%')
  GROUP BY p.hadm_id
),

-- Step 3: Calculate in-hospital mortality and LOS
admission_details AS (
  SELECT a.hadm_id, 
         a.hospital_expire_flag,
         DATETIME_DIFF(a.dischtime, a.admittime, DAY) AS los
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN patient_filter p ON a.hadm_id = p.hadm_id
),

-- Step 4: Count comorbidities
comorbidity_count AS (
  SELECT di.hadm_id, COUNT(DISTINCT di.icd_code) AS comorbidity_cnt,
         MAX(CASE WHEN d.icd_code IN ('N18.9', 'N18.1', 'N18.2', 'N18.3', 'N18.4', 'N18.5', 'N18.6', 'N18.8') THEN 1 ELSE 0 END) AS ckd_flag,
         MAX(CASE WHEN d.icd_code LIKE 'E11%' THEN 1 ELSE 0 END) AS diabetes_flag
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` di
  JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` d ON di.icd_code = d.icd_code AND di.icd_version = d.icd_version
  JOIN patient_filter p ON di.hadm_id = p.hadm_id
  WHERE di.icd_version = 10
  GROUP BY di.hadm_id
)

-- Final query
SELECT 
  CASE 
    WHEN sn.stemi_flag = 1 AND sn.nstemi_flag = 0 THEN 'STEMI'
    WHEN sn.stemi_flag = 0 AND sn.nstemi_flag = 1 THEN 'NSTEMI'
    ELSE 'Other'
  END AS MI_type,
  COUNT(a.hadm_id) AS N,
  AVG(a.hospital_expire_flag) * 100 AS in_hospital_mortality,
  COUNT(CASE WHEN a.los BETWEEN 1 AND 2 THEN 1 END) AS los_1_2,
  COUNT(CASE WHEN a.los BETWEEN 3 AND 5 THEN 1 END) AS los_3_5,
  COUNT(CASE WHEN a.los BETWEEN 6 AND 9 THEN 1 END) AS los_6_9,
  COUNT(CASE WHEN a.los >= 10 THEN 1 END) AS los_ge_10,
  COUNT(CASE WHEN cc.comorbidity_cnt BETWEEN 0 AND 1 THEN 1 END) AS comorbidity_0_1,
  COUNT(CASE WHEN cc.comorbidity_cnt = 2 THEN 1 END) AS comorbidity_2,
  COUNT(CASE WHEN cc.comorbidity_cnt >= 3 THEN 1 END) AS comorbidity_ge_3,
  AVG(cc.ckd_flag) * 100 AS ckd_prevalence,
  AVG(cc.diabetes_flag) * 100 AS diabetes_prevalence
FROM admission_details a
JOIN stem_nstem sn ON a.hadm_id = sn.hadm_id
JOIN comorbidity_count cc ON a.hadm_id = cc.hadm_id
GROUP BY MI_type
ORDER BY MI_type;