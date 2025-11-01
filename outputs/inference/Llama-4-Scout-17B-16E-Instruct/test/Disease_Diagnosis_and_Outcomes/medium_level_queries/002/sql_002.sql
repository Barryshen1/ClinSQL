WITH 
-- Identify patients of interest
patients_of_interest AS (
  SELECT 
    a.subject_id,
    a.hadm_id,
    p.anchor_age,
    p.gender,
    a.admittime,
    a.dischtime,
    a.deathtime,
    a.hospital_expire_flag,
    icu.stay_id,
    icu.intime AS icu_intime,
    icu.outtime AS icu_outtime
  FROM 
    `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN 
    `physionet-data.mimiciv_3_1_hosp.patients` p 
      ON a.subject_id = p.subject_id
  LEFT JOIN 
    `physionet-data.mimiciv_3_1_icu.icustays` icu 
      ON a.hadm_id = icu.hadm_id
  WHERE 
    p.gender = 'F'
    AND p.anchor_age BETWEEN 62 AND 72
    AND EXISTS (
      SELECT 1
      FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
      JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` dd 
        ON d.icd_code = dd.icd_code AND d.icd_version = dd.icd_version
      WHERE d.hadm_id = a.hadm_id AND dd.long_title LIKE '%Acute myocardial infarction%'
    )
    -- Exclude shock and respiratory failure; assume ICD codes for simplicity
    AND NOT EXISTS (
      SELECT 1
      FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
      JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` dd 
        ON d.icd_code = dd.icd_code AND d.icd_version = dd.icd_version
      WHERE d.hadm_id = a.hadm_id AND (dd.long_title LIKE '%Shock%' OR dd.long_title LIKE '%Respiratory failure%')
    )
),

-- Calculate length of stay (LOS)
los_group AS (
  SELECT 
    subject_id,
    hadm_id,
    hospital_expire_flag,
    CASE 
      WHEN deathtime IS NOT NULL THEN TIMESTAMP_DIFF(deathtime, admittime, DAY)
      WHEN dischtime IS NOT NULL THEN TIMESTAMP_DIFF(dischtime, admittime, DAY)
      ELSE NULL
    END AS los
  FROM 
    patients_of_interest
),

-- Group by LOS
los_category AS (
  SELECT 
    subject_id,
    hadm_id,
    hospital_expire_flag,
    los,
    CASE 
      WHEN los <= 5 THEN 'LOS_5'
      WHEN los > 5 THEN 'LOS_>5'
      ELSE 'UNKNOWN'
    END AS los_group
  FROM 
    los_group
),

-- CKD and Diabetes prevalence
ckd_diabetes AS (
  SELECT 
    subject_id,
    hadm_id,
    CASE 
      WHEN EXISTS (
        SELECT 1
        FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
        JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` dd 
          ON d.icd_code = dd.icd_code AND d.icd_version = dd.icd_version
        WHERE d.hadm_id = hadm_id AND dd.long_title LIKE '%Chronic kidney disease%'
      ) THEN 1 ELSE 0
    END AS has_ckd,
    CASE 
      WHEN EXISTS (
        SELECT 1
        FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
        JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` dd 
          ON d.icd_code = dd.icd_code AND d.icd_version = dd.icd_version
        WHERE d.hadm_id = hadm_id AND dd.long_title LIKE '%Diabetes%'
      ) THEN 1 ELSE 0
    END AS has_diabetes
  FROM 
    patients_of_interest
)

-- Final analysis
SELECT 
  lcd.los_group,
  COUNT(DISTINCT lcd.hadm_id) AS total_patients,
  SUM(CASE WHEN lcd.hospital_expire_flag = 1 THEN 1 ELSE 0 END) AS in_hospital_deaths,
  AVG(CD.has_ckd) AS ckd_prevalence,
  AVG(CD.has_diabetes) AS diabetes_prevalence
FROM 
  los_category lcd
JOIN 
  ckd_diabetes CD ON lcd.hadm_id = CD.hadm_id
GROUP BY 
  lcd.los_group;