WITH 
  -- Patient population with heart failure
  heart_failure_patients AS (
    SELECT 
      a.subject_id, 
      a.hadm_id, 
      p.anchor_age, 
      p.gender
    FROM 
      `physionet-data.mimiciv_3_1_hosp.admissions` a
    JOIN 
      `physionet-data.mimiciv_3_1_hosp.patients` p 
        ON a.subject_id = p.subject_id
    JOIN 
      `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d 
        ON a.subject_id = d.subject_id AND a.hadm_id = d.hadm_id
    JOIN 
      `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` di 
        ON d.icd_code = di.icd_code AND d.icd_version = di.icd_version
    WHERE 
      p.gender = 'F' 
      AND p.anchor_age BETWEEN 83 AND 93
      AND di.long_title LIKE '%Heart Failure%'
  ),

  -- ICU stay information
  icu_stays AS (
    SELECT 
      subject_id, 
      hadm_id, 
      stay_id
    FROM 
      `physionet-data.mimiciv_3_1_icu.icustays`
  ),

  -- Comorbidity burden
  comorbidities AS (
    SELECT 
      subject_id, 
      hadm_id,
      COUNT(DISTINCT CASE 
        WHEN di.long_title LIKE '%Chronic kidney disease%' THEN 1 
        WHEN di.long_title LIKE '%Diabetes%' THEN 1 
        ELSE NULL 
      END) AS comorbidity_count
    FROM 
      `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d 
    JOIN 
      `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` di 
        ON d.icd_code = di.icd_code AND d.icd_version = di.icd_version
    GROUP BY 
      subject_id, 
      hadm_id
  ),

  -- LOS calculation
  los_calculation AS (
    SELECT 
      a.hadm_id, 
      TIMESTAMP_DIFF(a.dischtime, a.admittime, DAY) AS los
    FROM 
      `physionet-data.mimiciv_3_1_hosp.admissions` a
  ),

  -- Final patient data
  patient_data AS (
    SELECT 
      hfp.subject_id, 
      hfp.hadm_id, 
      COALESCE(icu.stay_id, NULL) AS icu_stay_id,
      los.los,
      com.comorbidity_count,
      CASE 
        WHEN a.hospital_expire_flag = 1 THEN 1 
        ELSE 0 
      END AS mortality
    FROM 
      heart_failure_patients hfp
    JOIN 
      `physionet-data.mimiciv_3_1_hosp.admissions` a 
        ON hfp.subject_id = a.subject_id AND hfp.hadm_id = a.hadm_id
    LEFT JOIN 
      icu_stays icu 
        ON hfp.subject_id = icu.subject_id AND hfp.hadm_id = icu.hadm_id
    JOIN 
      los_calculation los 
        ON hfp.hadm_id = los.hadm_id
    JOIN 
      comorbidities com 
        ON hfp.subject_id = com.subject_id AND hfp.hadm_id = com.hadm_id
  )

-- Stratification and outcome calculation
SELECT 
  -- Stratification criteria
  CASE 
    WHEN pd.icu_stay_id IS NOT NULL THEN 'ICU'
    ELSE 'Non-ICU'
  END AS icu_non_icu,
  CASE 
    WHEN pd.los < 8 THEN '<8'
    ELSE '≥8'
  END AS los_category,
  CASE 
    WHEN pd.comorbidity_count <= 1 THEN '0-1'
    WHEN pd.comorbidity_count = 2 THEN '2'
    ELSE '≥3'
  END AS comorbidity_burden,
  -- Outcomes
  AVG(pd.mortality) * 100 AS mortality_pct,
  APPROX_QUANTILES(pd.los, 0.5)[OFFSET(1)] AS median_los,
  SUM(CASE 
    WHEN di.long_title LIKE '%Chronic kidney disease%' THEN 1 
    ELSE 0 
  END) / COUNT(*) AS ckd_prevalence,
  SUM(CASE 
    WHEN di.long_title LIKE '%Diabetes%' THEN 1 
    ELSE 0 
  END) / COUNT(*) AS diabetes_prevalence
FROM 
  patient_data pd
JOIN 
  `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d 
    ON pd.subject_id = d.subject_id AND pd.hadm_id = d.hadm_id
JOIN 
  `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` di 
    ON d.icd_code = di.icd_code AND d.icd_version = di.icd_version
GROUP BY 
  CASE 
    WHEN pd.icu_stay_id IS NOT NULL THEN 'ICU'
    ELSE 'Non-ICU'
  END,
  CASE 
    WHEN pd.los < 8 THEN '<8'
    ELSE '≥8'
  END,
  CASE 
    WHEN pd.comorbidity_count <= 1 THEN '0-1'
    WHEN pd.comorbidity_count = 2 THEN '2'
    ELSE '≥3'
  END;