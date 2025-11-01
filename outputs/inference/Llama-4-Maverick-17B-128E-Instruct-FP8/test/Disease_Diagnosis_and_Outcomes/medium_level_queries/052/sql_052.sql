WITH 
-- Step 1: Filter patients by age and gender
filtered_patients AS (
  SELECT subject_id
  FROM `physionet-data.mimiciv_3_1_hosp.patients`
  WHERE gender = 'M' AND anchor_age BETWEEN 52 AND 62
),

-- Step 2: Get relevant admissions
relevant_admissions AS (
  SELECT 
    a.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    a.hospital_expire_flag,
    CASE WHEN i.stay_id IS NOT NULL THEN 'ICU' ELSE 'Non-ICU' END AS care_type,
    DATETIME_DIFF(a.dischtime, a.admittime, DAY) AS los
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  LEFT JOIN `physionet-data.mimiciv_3_1_icu.icustays` i ON a.hadm_id = i.hadm_id
  WHERE a.subject_id IN (SELECT subject_id FROM filtered_patients)
),

-- Step 3: Identify comorbidities
comorbidities AS (
  SELECT 
    d.hadm_id,
    COUNT(DISTINCT CASE WHEN d_icd.long_title LIKE '%CKD%' OR d_icd.long_title LIKE '%Chronic kidney disease%' THEN d.icd_code ELSE NULL END) AS ckd,
    COUNT(DISTINCT CASE WHEN d_icd.long_title LIKE '%Diabetes%' THEN d.icd_code ELSE NULL END) AS diabetes
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
  JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` d_icd ON d.icd_code = d_icd.icd_code AND d.icd_version = d_icd.icd_version
  GROUP BY d.hadm_id
),

-- Step 4: Calculate comorbidity tertiles
comorbidity_tertiles AS (
  SELECT 
    hadm_id,
    ckd,
    diabetes,
    NTILE(3) OVER (ORDER BY (ckd + diabetes)) AS comorbidity_tertile
  FROM comorbidities
),

-- Step 5: Combine data and calculate outcomes
combined_data AS (
  SELECT 
    ra.care_type,
    CASE WHEN ra.los <= 5 THEN 'LOS <= 5' ELSE 'LOS > 5' END AS los_category,
    ct.comorbidity_tertile,
    ra.hospital_expire_flag,
    ct.ckd,
    ct.diabetes
  FROM relevant_admissions ra
  JOIN comorbidity_tertiles ct ON ra.hadm_id = ct.hadm_id
)

-- Step 6: Calculate final metrics
SELECT 
  care_type,
  los_category,
  comorbidity_tertile,
  ROUND(AVG(hospital_expire_flag) * 100, 2) AS in_hospital_mortality,
  ROUND(AVG(CASE WHEN ckd > 0 THEN 1 ELSE 0 END) * 100, 2) AS ckd_prevalence,
  ROUND(AVG(CASE WHEN diabetes > 0 THEN 1 ELSE 0 END) * 100, 2) AS diabetes_prevalence
FROM combined_data
GROUP BY care_type, los_category, comorbidity_tertile
ORDER BY care_type, los_category, comorbidity_tertile;