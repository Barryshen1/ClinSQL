WITH 
  -- Define heart failure ICD codes
  heart_failure AS (
    SELECT icd_code
    FROM `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses`
    WHERE long_title LIKE '%Heart failure%'
  ),
  
  -- Identify patients with heart failure, age, and gender
  hf_patients AS (
    SELECT 
      a.subject_id, 
      a.hadm_id, 
      p.anchor_age,
      a.admittime,
      a.dischtime,
      a.deathtime,
      a.hospital_expire_flag
    FROM 
      `physionet-data.mimiciv_3_1_hosp.admissions` a
    JOIN 
      `physionet-data.mimiciv_3_1_hosp.patients` p
    ON 
      a.subject_id = p.subject_id
    WHERE 
      p.gender = 'M' 
      AND p.anchor_age BETWEEN 77 AND 87
      AND a.hadm_id IN (
        SELECT hadm_id
        FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd`
        WHERE icd_code IN (SELECT icd_code FROM heart_failure)
      )
  ),
  
  -- Determine day-1 ICU admission
  icu_admissions AS (
    SELECT 
      i.hadm_id,
      CASE 
        WHEN TIMESTAMP(i.intime) - TIMESTAMP(a.admittime) <= INTERVAL 1 DAY THEN 'ICU'
        ELSE 'Non-ICU'
      END AS day1_icu
    FROM 
      `physionet-data.mimiciv_3_1_icu.icustays` i
    JOIN 
      hf_patients a
    ON 
      i.hadm_id = a.hadm_id
  ),
  
  -- Calculate LOS
  los_data AS (
    SELECT 
      hadm_id,
      DATE_DIFF(LEAST(dischtime, TIMESTAMP_ADD(admittime, INTERVAL 1 DAY)), admittime) AS los
    FROM 
      hf_patients
  ),
  
  -- Identify CKD and diabetes
  ckd_diabetes AS (
    SELECT 
      subject_id,
      hadm_id,
      CASE 
        WHEN icd_code IN (
          SELECT icd_code 
          FROM `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` 
          WHERE long_title LIKE '%Chronic kidney disease%'
        ) THEN 'CKD'
        WHEN icd_code IN (
          SELECT icd_code 
          FROM `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` 
          WHERE long_title LIKE '%Diabetes%'
        ) THEN 'Diabetes'
        ELSE NULL
      END AS comorbidity
    FROM 
      `physionet-data.mimiciv_3_1_hosp.diagnoses_icd`
  )

SELECT 
  COALESCE(ic.day1_icu, 'Non-ICU') AS day1_icu,
  CASE 
    WHEN los.los BETWEEN 1 AND 3 THEN '1-3'
    WHEN los.los BETWEEN 4 AND 7 THEN '4-7'
    WHEN los.los >= 8 THEN '>=8'
    ELSE 'Unknown'
  END AS los_category,
  COUNT(DISTINCT CASE WHEN hp.hospital_expire_flag = 1 THEN hp.hadm_id END) / COUNT(DISTINCT hp.hadm_id) * 100 AS in_hospital_mortality_pct,
  APPROX_QUANTILES(los.los, 1000)[500] AS median_los,
  COUNT(DISTINCT CASE WHEN cd.comorbidity IN ('CKD', 'Diabetes') THEN cd.hadm_id END) / COUNT(DISTINCT cd.hadm_id) * 100 AS ckd_diabetes_prevalence
FROM 
  hf_patients hp
  LEFT JOIN icu_admissions ic ON hp.hadm_id = ic.hadm_id
  JOIN los_data los ON hp.hadm_id = los.hadm_id
  LEFT JOIN ckd_diabetes cd ON hp.hadm_id = cd.hadm_id AND cd.comorbidity IS NOT NULL
GROUP BY 
  ic.day1_icu, los_category
ORDER BY 
  ic.day1_icu, los_category;