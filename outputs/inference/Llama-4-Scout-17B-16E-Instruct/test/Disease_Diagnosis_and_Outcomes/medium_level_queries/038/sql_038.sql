WITH 
  -- Identify heart failure, CKD, and diabetes
  diagnoses AS (
    SELECT 
      di.subject_id,
      di.hadm_id,
      ddd.long_title,
      CASE 
        WHEN ddd.long_title LIKE '%Heart Failure%' THEN 1
        WHEN ddd.long_title LIKE '%Chronic kidney disease%' THEN 1
        WHEN ddd.long_title LIKE '%Diabetes%' THEN 1
        ELSE 0
      END AS has_heart_failure,
      CASE 
        WHEN ddd.long_title LIKE '%Chronic kidney disease%' THEN 1
        ELSE 0
      END AS has_ckd,
      CASE 
        WHEN ddd.long_title LIKE '%Diabetes%' THEN 1
        ELSE 0
      END AS has_diabetes
    FROM 
      `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` di
    JOIN 
      `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` ddd 
      ON di.icd_code = ddd.icd_code AND di.icd_version = ddd.icd_version
  ),
  
  -- Patient and admission information
  patient_info AS (
    SELECT 
      a.subject_id,
      a.hadm_id,
      p.gender,
      p.anchor_age,
      a.admittime,
      a.dischtime,
      a.deathtime,
      COALESCE(i.stay_id, NULL) AS stay_id,
      TIMESTAMP_DIFF(a.dischtime, a.admittime, DAY) AS los
    FROM 
      `physionet-data.mimiciv_3_1_hosp.admissions` a
    JOIN 
      `physionet-data.mimiciv_3_1_hosp.patients` p 
      ON a.subject_id = p.subject_id
    LEFT JOIN 
      `physionet-data.mimiciv_3_1_icu.icustays` i 
      ON a.hadm_id = i.hadm_id
  ),
  
  -- Aggregate information
  aggregated AS (
    SELECT 
      pi.subject_id,
      pi.hadm_id,
      pi.stay_id,
      pi.los,
      pi.gender,
      pi.anchor_age,
      SUM(di.has_heart_failure) > 0 AS has_heart_failure,
      SUM(di.has_ckd) > 0 AS has_ckd,
      SUM(di.has_diabetes) > 0 AS has_diabetes,
      CASE 
        WHEN pi.deathtime IS NOT NULL THEN 1
        ELSE 0
      END AS died_in_hospital
    FROM 
      patient_info pi
    LEFT JOIN 
      diagnoses di ON pi.hadm_id = di.hadm_id
    GROUP BY 
      pi.subject_id, pi.hadm_id, pi.stay_id, pi.los, pi.gender, pi.anchor_age, pi.deathtime
  )

-- Final query
SELECT 
  CASE 
    WHEN a.gender = 'F' AND a.anchor_age BETWEEN 80 AND 90 THEN 'Target Population'
    ELSE 'Other'
  END AS population,
  CASE 
    WHEN a.stay_id IS NOT NULL THEN 'ICU'
    ELSE 'Non-ICU'
  END AS icu_stay,
  CASE 
    WHEN a.los < 8 THEN '<8 days'
    ELSE '≥8 days'
  END AS los_category,
  AVG(a.died_in_hospital) AS in_hospital_mortality_rate,
  AVG(CASE WHEN a.has_ckd THEN 1 ELSE 0 END) AS ckd_prevalence,
  AVG(CASE WHEN a.has_diabetes THEN 1 ELSE 0 END) AS diabetes_prevalence
FROM 
  aggregated a
WHERE 
  a.gender = 'F' AND a.anchor_age BETWEEN 80 AND 90 AND a.has_heart_failure
GROUP BY 
  population, icu_stay, los_category
ORDER BY 
  population, icu_stay, los_category;