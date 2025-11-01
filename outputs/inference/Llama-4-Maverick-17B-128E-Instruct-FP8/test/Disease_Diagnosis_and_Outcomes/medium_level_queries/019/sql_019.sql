WITH 
-- Step 1: Identify heart failure patients and filter by age and gender
hf_patients AS (
  SELECT DISTINCT p.subject_id, p.anchor_age, p.gender, di.long_title
  FROM `physionet-data.mimiciv_3_1_hosp.patients` p
  JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` di_c ON p.subject_id = di_c.subject_id
  JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` di ON di_c.icd_code = di.icd_code AND di_c.icd_version = di.icd_version
  WHERE p.gender = 'M' AND p.anchor_age BETWEEN 53 AND 63
  AND di.long_title LIKE '%Heart failure%'
),

-- Step 2: Calculate in-hospital mortality, LOS, and discharge destination
admissions_data AS (
  SELECT a.subject_id, a.hadm_id, a.hospital_expire_flag, 
         DATETIME_DIFF(a.dischtime, a.admittime, DAY) AS los,
         a.discharge_location
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN hf_patients ON a.subject_id = hf_patients.subject_id
),

-- Step 3: Calculate Charlson Comorbidity Index
charlson AS (
  SELECT di_c.subject_id, di_c.hadm_id, 
         SUM(CASE 
             WHEN di.icd_code IN ('410.0', '410.1', '410.2', '410.3', '410.4', '410.5', '410.6', '410.7', '410.8', '410.9') THEN 1
             WHEN di.icd_code LIKE '428%' THEN 1
             WHEN di.icd_code LIKE '584%' OR di.icd_code LIKE '585%' THEN 2
             -- Add more conditions here as per Charlson Comorbidity Index definition
             ELSE 0
             END) AS charlson_score
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` di_c
  JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` di ON di_c.icd_code = di.icd_code AND di_c.icd_version = di.icd_version
  JOIN hf_patients ON di_c.subject_id = hf_patients.subject_id
  GROUP BY di_c.subject_id, di_c.hadm_id
),

-- Step 4: Prepare data for final analysis
prepared_data AS (
  SELECT 
    a.los,
    a.hospital_expire_flag,
    a.discharge_location,
    CASE 
      WHEN a.los BETWEEN 1 AND 3 THEN '1-3'
      WHEN a.los BETWEEN 4 AND 7 THEN '4-7'
      ELSE '>=8'
    END AS los_category,
    CASE 
      WHEN c.charlson_score <= 3 THEN '<=3'
      WHEN c.charlson_score BETWEEN 4 AND 5 THEN '4-5'
      ELSE '>5'
    END AS charlson_category
  FROM admissions_data a
  JOIN charlson c ON a.hadm_id = c.hadm_id
)

-- Final analysis
SELECT 
  los_category,
  charlson_category,
  AVG(hospital_expire_flag) * 100 AS in_hospital_mortality_pct,
  COUNT(*) AS count_patients,
  PERCENTILE_CONT(los, 0.5) AS median_los,
  PERCENTILE_CONT(los, 0.75) - PERCENTILE_CONT(los, 0.25) AS iqr_los,
  COUNT(CASE WHEN discharge_location = 'HOME' THEN 1 END) * 100.0 / COUNT(*) AS discharge_home_pct,
  COUNT(CASE WHEN discharge_location LIKE '%REHAB%' THEN 1 END) * 100.0 / COUNT(*) AS discharge_rehab_pct,
  COUNT(CASE WHEN discharge_location LIKE '%SNF%' THEN 1 END) * 100.0 / COUNT(*) AS discharge_snf_pct,
  COUNT(CASE WHEN discharge_location LIKE '%HOSPICE%' THEN 1 END) * 100.0 / COUNT(*) AS discharge_hospice_pct
FROM prepared_data
GROUP BY los_category, charlson_category
ORDER BY los_category, charlson_category;