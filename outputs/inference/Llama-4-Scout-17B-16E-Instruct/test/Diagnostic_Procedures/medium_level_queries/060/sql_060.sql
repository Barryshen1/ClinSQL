WITH 
  -- Filter patients of interest
  target_patients AS (
    SELECT 
      p.subject_id, 
      p.anchor_age,
      a.hadm_id,
      a.admittime,
      a.dischtime,
      TIMESTAMP_DIFF(a.dischtime, a.admittime, DAY) AS hospital_los
    FROM 
      `physionet-data.mimiciv_3_1_hosp.patients` p
    JOIN 
      `physionet-data.mimiciv_3_1_hosp.admissions` a 
        ON p.subject_id = a.subject_id
    WHERE 
      p.gender = 'M' 
      AND p.anchor_age BETWEEN 49 AND 59
      AND a.admission_type = 'elective'  -- Assuming primary heart failure is often elective for simplicity
  ),
  
  -- Identify primary heart failure diagnosis
  heart_failure_admissions AS (
    SELECT 
      hadm_id
    FROM 
      `physionet-data.mimiciv_3_1_hosp.diagnoses_icd`
    WHERE 
      icd_code LIKE '402%'  -- Example ICD code for heart failure; adjust as necessary
      AND seq_num = 1  -- Primary diagnosis
  ),
  
  -- ICU stays and their durations
  icu_stays AS (
    SELECT 
      subject_id, 
      hadm_id, 
      stay_id,
      TIMESTAMP_DIFF(outtime, intime, DAY) AS icu_los
    FROM 
      `physionet-data.mimiciv_3_1_icu.icustays`
  ),
  
  -- Admissions with CT/MRI
  ct_mri_admissions AS (
    SELECT 
      hadm_id,
      COUNT(DISTINCT icd_code) AS ct_mri_count
    FROM 
      `physionet-data.mimiciv_3_1_hosp.procedures_icd`
    WHERE 
      icd_code LIKE '87%' OR icd_code LIKE '88%'  -- CT/MRI procedure codes
    GROUP BY 
      hadm_id
  )

SELECT 
  CASE 
    WHEN i.stay_id IS NOT NULL THEN 'ICU'
    ELSE 'Non-ICU'
  END AS icu_utilization,
  CASE 
    WHEN COALESCE(i.icu_los, 0) BETWEEN 1 AND 4 THEN '1-4 days'
    WHEN COALESCE(i.icu_los, 0) BETWEEN 5 AND 7 THEN '5-7 days'
    ELSE 'Outside range'
  END AS icu_los_category,
  COUNT(DISTINCT tp.hadm_id) AS admission_counts,
  COALESCE(AVG(ctma.ct_mri_count), 0) AS mean_ct_mri_per_admission
FROM 
  target_patients tp
  JOIN heart_failure_admissions hf ON tp.hadm_id = hf.hadm_id
  LEFT JOIN icu_stays i ON tp.hadm_id = i.hadm_id
  LEFT JOIN ct_mri_admissions ctma ON tp.hadm_id = ctma.hadm_id
GROUP BY 
  icu_utilization,
  icu_los_category
ORDER BY 
  icu_utilization,
  icu_los_category;