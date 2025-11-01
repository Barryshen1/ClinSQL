WITH 
-- Step 1: Filter patients based on age and gender
eligible_patients AS (
  SELECT subject_id
  FROM `physionet-data.mimiciv_3_1_hosp.patients`
  WHERE gender = 'F' AND anchor_age BETWEEN 52 AND 62
),

-- Step 2: Identify stroke type (ischemic vs. hemorrhagic)
stroke_type AS (
  SELECT DISTINCT hadm_id, 
         CASE 
           WHEN icd_code LIKE 'I63%' THEN 'Ischemic'
           WHEN icd_code LIKE 'I61%' OR icd_code LIKE 'I62%' THEN 'Hemorrhagic'
           ELSE NULL
         END AS stroke_type
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd`
  WHERE icd_version = 10 AND (icd_code LIKE 'I63%' OR icd_code LIKE 'I61%' OR icd_code LIKE 'I62%')
),

-- Step 3: Calculate in-hospital mortality and LOS
patient_outcomes AS (
  SELECT a.hadm_id, 
         a.hospital_expire_flag,
         DATETIME_DIFF(a.dischtime, a.admittime, DAY) AS los
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN eligible_patients e ON a.subject_id = e.subject_id
),

-- Step 4: Identify CKD and diabetes
comorbidities AS (
  SELECT di.hadm_id, 
         COUNT(DISTINCT di.icd_code) AS num_comorbidities,
         MAX(CASE WHEN d.long_title LIKE '%Diabetes%' THEN 1 ELSE 0 END) AS has_diabetes,
         MAX(CASE WHEN d.long_title LIKE '%Chronic kidney disease%' THEN 1 ELSE 0 END) AS has_ckd
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` di
  JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` d ON di.icd_code = d.icd_code AND di.icd_version = d.icd_version
  WHERE di.icd_version = 10
  GROUP BY di.hadm_id
),

-- Step 5: Combine data and calculate tertiles of comorbidity
combined_data AS (
  SELECT s.hadm_id, s.stroke_type, po.hospital_expire_flag, po.los, c.num_comorbidities, c.has_diabetes, c.has_ckd
  FROM stroke_type s
  JOIN patient_outcomes po ON s.hadm_id = po.hadm_id
  JOIN comorbidities c ON s.hadm_id = c.hadm_id
),

-- Calculate tertiles of comorbidity count
comorbidity_tertiles AS (
  SELECT hadm_id, num_comorbidities,
         NTILE(3) OVER (ORDER BY num_comorbidities) AS comorbidity_tertile
  FROM combined_data
)

-- Final analysis
SELECT 
  s.stroke_type,
  ct.comorbidity_tertile,
  AVG(s.hospital_expire_flag) * 100 AS in_hospital_mortality_pct,
  APPROX_QUANTILES(s.los, 100)[OFFSET(50)] AS median_los,
  AVG(s.has_diabetes) * 100 AS diabetes_prevalence,
  AVG(s.has_ckd) * 100 AS ckd_prevalence,
  SUM(CASE WHEN s.los < 8 THEN 1 ELSE 0 END) / COUNT(*) * 100 AS los_lt_8_days_pct,
  SUM(CASE WHEN s.los >= 8 THEN 1 ELSE 0 END) / COUNT(*) * 100 AS los_ge_8_days_pct
FROM combined_data s
JOIN comorbidity_tertiles ct ON s.hadm_id = ct.hadm_id
GROUP BY s.stroke_type, ct.comorbidity_tertile
ORDER BY s.stroke_type, ct.comorbidity_tertile;