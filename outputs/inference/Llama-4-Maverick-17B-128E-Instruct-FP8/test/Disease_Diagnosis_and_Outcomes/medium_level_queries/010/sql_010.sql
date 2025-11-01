WITH 
-- Step 1: Filter patients based on age and gender
eligible_patients AS (
  SELECT subject_id
  FROM `physionet-data.mimiciv_3_1_hosp.patients`
  WHERE gender = 'M' AND anchor_age BETWEEN 78 AND 88
),

-- Step 2: Identify admissions for AMI without shock or respiratory failure
ami_admissions AS (
  SELECT a.hadm_id, a.subject_id, a.admittime, a.dischtime, a.hospital_expire_flag,
         EXTRACT(YEAR FROM a.admittime) AS year_admitted
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN eligible_patients p ON a.subject_id = p.subject_id
  WHERE a.hadm_id IN (
    SELECT hadm_id
    FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd`
    WHERE icd_code IN (SELECT icd_code FROM `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` WHERE long_title LIKE '%Myocardial infarction%')
  )
  AND a.hadm_id NOT IN (
    SELECT hadm_id
    FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd`
    WHERE icd_code IN (SELECT icd_code FROM `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` WHERE long_title LIKE '%Shock%' OR long_title LIKE '%Respiratory failure%')
  )
),

-- Step 3: Calculate LOS and categorize by quartile
los_quartile AS (
  SELECT hadm_id, 
         DATETIME_DIFF(dischtime, admittime, HOUR) AS los_hours,
         NTILE(4) OVER (ORDER BY DATETIME_DIFF(dischtime, admittime, HOUR)) AS los_quartile
  FROM ami_admissions
),

-- Step 4: Assess comorbidity burden using Elixhauser Comorbidity Index (simplified)
comorbidity_burden AS (
  SELECT hadm_id, COUNT(DISTINCT icd_code) AS comorbidity_count
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd`
  WHERE hadm_id IN (SELECT hadm_id FROM ami_admissions)
  AND icd_code NOT IN (SELECT icd_code FROM `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` WHERE long_title LIKE '%Myocardial infarction%')
  GROUP BY hadm_id
),

-- Step 5: Categorize comorbidity burden
comorbidity_category AS (
  SELECT hadm_id,
         CASE
           WHEN comorbidity_count <= 2 THEN 'Low'
           WHEN comorbidity_count BETWEEN 3 AND 5 THEN 'Medium'
           ELSE 'High'
         END AS comorbidity_category
  FROM comorbidity_burden
),

-- Step 6: Determine CKD and diabetes prevalence
comorbid_conditions AS (
  SELECT hadm_id,
         MAX(CASE WHEN icd_code IN (SELECT icd_code FROM `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` WHERE long_title LIKE '%Chronic kidney disease%') THEN 1 ELSE 0 END) AS has_ckd,
         MAX(CASE WHEN icd_code IN (SELECT icd_code FROM `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` WHERE long_title LIKE '%Diabetes%') THEN 1 ELSE 0 END) AS has_diabetes
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd`
  WHERE hadm_id IN (SELECT hadm_id FROM ami_admissions)
  GROUP BY hadm_id
)

-- Final analysis
SELECT 
  lq.los_quartile,
  cc.comorbidity_category,
  COUNT(*) AS total_patients,
  SUM(aa.hospital_expire_flag) AS in_hospital_deaths,
  SUM(ccd.has_ckd) AS ckd_count,
  SUM(ccd.has_diabetes) AS diabetes_count,
  -- 95% CI for in-hospital mortality
  SUM(aa.hospital_expire_flag) / COUNT(*) AS mortality_proportion,
  -- Using APPROX_QUANTILES or other methods might be more accurate for CI with large datasets
  SUM(aa.hospital_expire_flag) / COUNT(*) - 1.96 * SQRT((SUM(aa.hospital_expire_flag) / COUNT(*)) * (1 - SUM(aa.hospital_expire_flag) / COUNT(*)) / COUNT(*)) AS lower_ci,
  SUM(aa.hospital_expire_flag) / COUNT(*) + 1.96 * SQRT((SUM(aa.hospital_expire_flag) / COUNT(*)) * (1 - SUM(aa.hospital_expire_flag) / COUNT(*)) / COUNT(*)) AS upper_ci
FROM ami_admissions aa
JOIN los_quartile lq ON aa.hadm_id = lq.hadm_id
JOIN comorbidity_category cc ON aa.hadm_id = cc.hadm_id
JOIN comorbid_conditions ccd ON aa.hadm_id = ccd.hadm_id
GROUP BY lq.los_quartile, cc.comorbidity_category
ORDER BY lq.los_quartile, cc.comorbidity_category;