WITH 
-- Step 1: Filter patients based on age and gender
filtered_patients AS (
  SELECT subject_id
  FROM `physionet-data.mimiciv_3_1_hosp.patients`
  WHERE gender = 'M' AND anchor_age BETWEEN 82 AND 92
),

-- Step 2: Identify postoperative patients
postoperative_patients AS (
  SELECT DISTINCT hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.procedures_icd`
),

-- Step 3: Calculate comorbidity count using Elixhauser Comorbidity Index (simplified)
comorbidity_count AS (
  SELECT hadm_id, COUNT(DISTINCT icd_code) as comorbidity_cnt
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd`
  WHERE icd_version = 10  -- Assuming ICD-10, adjust as necessary
  AND icd_code IN (SELECT icd_code FROM `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` WHERE icd_version = 10)
  GROUP BY hadm_id
),

-- Step 4: Classify admissions into ICU vs non-ICU and calculate LOS
admission_details AS (
  SELECT 
    a.hadm_id,  -- Explicitly selecting hadm_id from 'a'
    a.admittime,
    a.dischtime,
    a.hospital_expire_flag,
    CASE WHEN i.stay_id IS NOT NULL THEN 'ICU' ELSE 'non-ICU' END AS icu_status,
    DATETIME_DIFF(a.dischtime, a.admittime, DAY) AS los
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  LEFT JOIN `physionet-data.mimiciv_3_1_icu.icustays` i ON a.hadm_id = i.hadm_id
),

-- Step 5: Combine data and apply filters
combined_data AS (
  SELECT 
    ad.hadm_id,
    ad.icu_status,
    ad.los,
    ad.hospital_expire_flag,
    cc.comorbidity_cnt,
    CASE 
      WHEN cc.comorbidity_cnt BETWEEN 0 AND 1 THEN '0-1'
      WHEN cc.comorbidity_cnt = 2 THEN '2'
      ELSE '>=3'
    END AS comorbidity_bin,
    CASE WHEN ad.los <= 5 THEN 'LOS <= 5' ELSE 'LOS > 5' END AS los_category
  FROM admission_details ad
  JOIN comorbidity_count cc ON ad.hadm_id = cc.hadm_id
  WHERE ad.hadm_id IN (SELECT hadm_id FROM postoperative_patients)
  AND ad.hadm_id IN (SELECT hadm_id FROM filtered_patients JOIN `physionet-data.mimiciv_3_1_hosp.admissions` ON filtered_patients.subject_id = `physionet-data.mimiciv_3_1_hosp.admissions`.subject_id)
)

-- Step 6: Aggregate data
SELECT 
  icu_status,
  los_category,
  comorbidity_bin,
  COUNT(*) AS N,
  AVG(hospital_expire_flag) * 100 AS in_hospital_mortality_pct,
  AVG(comorbidity_cnt) AS avg_comorbidity_count
FROM combined_data
GROUP BY icu_status, los_category, comorbidity_bin
ORDER BY icu_status, los_category, comorbidity_bin;