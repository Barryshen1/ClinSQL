WITH 
  -- Filter patients by age and gender
  target_patients AS (
    SELECT subject_id
    FROM `physionet-data.mimiciv_3_1_hosp.patients`
    WHERE gender = 'M' AND anchor_age BETWEEN 62 AND 72
  ),
  
  -- Extract heart rate data for target patients
  heart_rate_data AS (
    SELECT 
      ic.stay_id,
      ic.hadm_id,
      ic.subject_id,
      ce.valuenum AS heart_rate
    FROM 
      `physionet-data.mimiciv_3_1_icu.icustays` ic
    JOIN 
      `physionet-data.mimiciv_3_1_icu.chartevents` ce
    ON 
      ic.stay_id = ce.stay_id
    WHERE 
      ic.subject_id IN (SELECT subject_id FROM target_patients)
      AND ce.itemid = 220050  -- Heart rate itemid
      AND ce.valuenum IS NOT NULL
  ),
  
  -- Categorize heart rates
  heart_rate_categories AS (
    SELECT 
      hd.hadm_id,
      hd.stay_id,
      hd.subject_id,
      CASE
        WHEN hd.heart_rate < 60 THEN '<60'
        WHEN hd.heart_rate BETWEEN 60 AND 99 THEN '60–99'
        WHEN hd.heart_rate BETWEEN 100 AND 119 THEN '100–119'
        ELSE '≥120'
      END AS heart_rate_category
    FROM 
      heart_rate_data hd
  ),
  
  -- Identify acute MI
  acute_mi_patients AS (
    SELECT DISTINCT 
      di.hadm_id,
      di.subject_id
    FROM 
      `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` di
    WHERE 
      (di.icd_code LIKE '410%' AND di.icd_version = '9')  -- ICD-9
      OR (di.icd_code LIKE 'I24%' AND di.icd_version = '10')  -- ICD-10
  )

-- Final query
SELECT 
  hr_category AS heart_rate_category,
  COUNT(DISTINCT stay_id) AS count_icustays,
  SUM(CASE WHEN am.hadm_id IS NOT NULL THEN 1 ELSE 0 END) / COUNT(DISTINCT stay_id) * 100 AS percent_with_acute_mi
FROM 
  (SELECT 
     hadm_id,
     stay_id,
     subject_id,
     heart_rate_category AS hr_category
   FROM 
     heart_rate_categories
  ) hr
  LEFT JOIN acute_mi_patients am
  USING (hadm_id, subject_id)
GROUP BY 
  hr.hr_category
ORDER BY 
  hr.hr_category;