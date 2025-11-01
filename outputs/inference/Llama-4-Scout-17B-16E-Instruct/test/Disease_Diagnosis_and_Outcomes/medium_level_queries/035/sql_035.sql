WITH 
  -- Identify upper and lower GI bleed cases
  gi_bleed AS (
    SELECT 
      di.subject_id,
      di.hadm_id,
      CASE 
        WHEN d_icd.long_title LIKE '%Upper GI bleed%' THEN 'Upper GI bleed'
        WHEN d_icd.long_title LIKE '%Lower GI bleed%' THEN 'Lower GI bleed'
        ELSE 'Other'
      END AS bleed_type
    FROM 
      `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` di
    JOIN 
      `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` d_icd
    ON 
      di.icd_code = d_icd.icd_code AND di.icd_version = d_icd.icd_version
  ),
  
  -- Patient demographics and admission details
  patient_details AS (
    SELECT 
      a.subject_id,
      a.hadm_id,
      p.anchor_age,
      p.gender,
      a.admittime,
      a.dischtime,
      a.deathtime,
      a.hospital_expire_flag,
      TIMESTAMP_DIFF(a.dischtime, a.admittime, DAY) AS los
    FROM 
      `physionet-data.mimiciv_3_1_hosp.admissions` a
    JOIN 
      `physionet-data.mimiciv_3_1_hosp.patients` p
    ON 
      a.subject_id = p.subject_id
  ),
  
  -- ICU stay details
  icu_stays AS (
    SELECT 
      subject_id,
      hadm_id,
      stay_id,
      intime,
      TIMESTAMP_DIFF(outtime, intime, DAY) AS icu_los
    FROM 
      `physionet-data.mimiciv_3_1_icu.icustays`
  ),
  
  -- Combine patient details with GI bleed type and ICU stay
  combined AS (
    SELECT 
      pd.subject_id,
      pd.hadm_id,
      pd.anchor_age,
      pd.gender,
      pd.admittime,
      pd.dischtime,
      pd.deathtime,
      pd.hospital_expire_flag,
      pd.los,
      gb.bleed_type,
      CASE 
        WHEN icu.intime IS NOT NULL AND TIMESTAMP_DIFF(icu.intime, pd.admittime, DAY) = 0 THEN 'Yes'
        ELSE 'No'
      END AS day1_icu
    FROM 
      patient_details pd
    LEFT JOIN 
      gi_bleed gb
    ON 
      pd.hadm_id = gb.hadm_id
    LEFT JOIN 
      icu_stays icu
    ON 
      pd.hadm_id = icu.hadm_id AND pd.admittime = icu.intime
  )

-- Final analysis
SELECT 
  bleed_type,
  CASE 
    WHEN los BETWEEN 1 AND 2 THEN '1-2 days'
    WHEN los BETWEEN 3 AND 5 THEN '3-5 days'
    WHEN los BETWEEN 6 AND 9 THEN '6-9 days'
    ELSE '>=10 days'
  END AS los_category,
  day1_icu,
  COUNT(DISTINCT hadm_id) AS total_patients,
  SUM(CASE WHEN hospital_expire_flag = 1 THEN 1 ELSE 0 END) AS deaths,
  SUM(CASE WHEN hospital_expire_flag = 1 THEN 1 ELSE 0 END) / COUNT(DISTINCT hadm_id) AS mortality_rate,
  COUNT(DISTINCT CASE WHEN day1_icu = 'Yes' THEN hadm_id END) / COUNT(DISTINCT hadm_id) AS icu_admission_rate
FROM 
  combined
WHERE 
  anchor_age BETWEEN 69 AND 79 AND gender = 'F' AND bleed_type IN ('Upper GI bleed', 'Lower GI bleed')
GROUP BY 
  bleed_type,
  los_category,
  day1_icu
ORDER BY 
  bleed_type,
  los_category,
  day1_icu;