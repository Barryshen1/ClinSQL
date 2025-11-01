WITH 
  -- Patient selection and basic information
  patients_base AS (
    SELECT 
      a.subject_id,
      a.hadm_id,
      p.anchor_age,
      p.gender,
      a.admission_type,
      CASE 
        WHEN ic.stay_id IS NOT NULL THEN 'ICU'
        ELSE 'Non-ICU'
      END AS care_type,
      a.hospital_expire_flag,
      a.deathtime,
      EXTRACT(DAY FROM a.dischtime - a.admittime) AS los_days
    FROM 
      `physionet-data.mimiciv_3_1_hosp.admissions` a
    JOIN 
      `physionet-data.mimiciv_3_1_hosp.patients` p 
      ON a.subject_id = p.subject_id
    LEFT JOIN 
      `physionet-data.mimiciv_3_1_icu.icustays` ic 
      ON a.hadm_id = ic.hadm_id
    WHERE 
      p.gender = 'M' 
      AND p.anchor_age BETWEEN 51 AND 61
      AND a.admission_type = 'postoperative'
  ),
  
  -- LOS categorization
  patients_los AS (
    SELECT 
      subject_id,
      hadm_id,
      care_type,
      hospital_expire_flag,
      deathtime,
      los_days,
      CASE 
        WHEN los_days BETWEEN 1 AND 2 THEN '1-2'
        WHEN los_days BETWEEN 3 AND 5 THEN '3-5'
        WHEN los_days BETWEEN 6 AND 9 THEN '6-9'
        ELSE '>=10'
      END AS los_category
    FROM 
      patients_base
  ),
  
  -- Charlson comorbidity index approximation (simplified)
  charlson_index AS (
    SELECT 
      subject_id,
      hadm_id,
      -- Simplified example, actual calculation is more complex
      COUNT(DISTINCT icd_code) AS charlson_score
    FROM 
      `physionet-data.mimiciv_3_1_hosp.diagnoses_icd`
    GROUP BY 
      subject_id, hadm_id
  ),
  
  -- CKD and Diabetes prevalence
  comorbidities AS (
    SELECT 
      subject_id,
      hadm_id,
      CASE 
        WHEN icd_code LIKE '%585%' THEN 'CKD'
        WHEN icd_code LIKE '%250%' THEN 'Diabetes'
        ELSE NULL
      END AS comorbidity
    FROM 
      `physionet-data.mimiciv_3_1_hosp.diagnoses_icd`
  ),
  
  -- Final patient data with outcomes
  patient_outcomes AS (
    SELECT 
      pl.subject_id,
      pl.hadm_id,
      pl.care_type,
      pl.los_category,
      ci.charlson_score,
      pl.hospital_expire_flag,
      pl.deathtime,
      pl.los_days,
      c.comorbidity
    FROM 
      patients_los pl
    LEFT JOIN 
      charlson_index ci 
      ON pl.subject_id = ci.subject_id AND pl.hadm_id = ci.hadm_id
    LEFT JOIN 
      comorbidities c 
      ON pl.subject_id = c.subject_id AND pl.hadm_id = c.hadm_id
  )

-- Final query for mortality, median LOS, CKD, and diabetes prevalence
SELECT 
  care_type,
  los_category,
  -- Charlson comorbidity categories
  CASE 
    WHEN charlson_score BETWEEN 0 AND 1 THEN '0-1'
    WHEN charlson_score = 2 THEN '2'
    ELSE '>=3'
  END AS charlson_category,
  COUNT(DISTINCT CASE WHEN hospital_expire_flag = 1 OR deathtime IS NOT NULL THEN hadm_id END) / COUNT(DISTINCT hadm_id) * 100 AS mortality_pct,
  APPROX_QUANTILES(los_days, 100)[OFFSET(50)] AS median_los,
  COUNT(DISTINCT CASE WHEN comorbidity = 'CKD' THEN hadm_id END) / COUNT(DISTINCT hadm_id) * 100 AS ckd_prevalence,
  COUNT(DISTINCT CASE WHEN comorbidity = 'Diabetes' THEN hadm_id END) / COUNT(DISTINCT hadm_id) * 100 AS diabetes_prevalence
FROM 
  patient_outcomes
GROUP BY 
  care_type,
  los_category,
  CASE 
    WHEN charlson_score BETWEEN 0 AND 1 THEN '0-1'
    WHEN charlson_score = 2 THEN '2'
    ELSE '>=3'
  END;