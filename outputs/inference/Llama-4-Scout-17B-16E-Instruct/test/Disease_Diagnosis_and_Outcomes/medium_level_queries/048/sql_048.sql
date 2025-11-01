WITH 
  -- Patient demographics and admission information
  patient_info AS (
    SELECT 
      p.subject_id,
      p.anchor_age,
      p.gender,
      a.hadm_id,
      a.admittime,
      a.dischtime,
      a.hospital_expire_flag,
      COALESCE(a.dischtime, a.deathtime) AS discharge_time
    FROM 
      `physionet-data.mimiciv_3_1_hosp.patients` p
    JOIN 
      `physionet-data.mimiciv_3_1_hosp.admissions` a
    ON 
      p.subject_id = a.subject_id
    WHERE 
      p.gender = 'M' AND p.anchor_age BETWEEN 68 AND 78
  ),
  
  -- CKD and diabetes diagnoses
  diagnoses_info AS (
    SELECT 
      subject_id,
      hadm_id,
      icd_code
    FROM 
      `physionet-data.mimiciv_3_1_hosp.diagnoses_icd`
  ),
  
  -- LOS calculation
  los_info AS (
    SELECT 
      p.hadm_id,
      TIMESTAMP_DIFF(p.discharge_time, p.admittime, DAY) AS los
    FROM 
      patient_info p
  )

SELECT 
  -- Stratification by LOS
  CASE 
    WHEN l.los < 8 THEN 'LOS < 8 days'
    ELSE 'LOS ≥ 8 days'
  END AS los_category,
  
  -- In-hospital mortality
  AVG(CASE WHEN p.hospital_expire_flag = 1 THEN 1 ELSE 0 END) * 100 AS in_hospital_mortality_pct,
  
  -- CKD prevalence
  AVG(CASE 
        WHEN d.icd_code IN (
          SELECT icd_code 
          FROM `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` 
          WHERE long_title LIKE '%Chronic kidney disease%'
        ) THEN 1 ELSE 0 
      END) * 100 AS ckd_prevalence_pct,
  
  -- Diabetes prevalence
  AVG(CASE 
        WHEN d.icd_code IN (
          SELECT icd_code 
          FROM `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` 
          WHERE long_title LIKE '%Diabetes%'
        ) THEN 1 ELSE 0 
      END) * 100 AS diabetes_prevalence_pct

FROM 
  patient_info p
JOIN 
  los_info l
ON 
  p.hadm_id = l.hadm_id
LEFT JOIN 
  diagnoses_info d
ON 
  p.hadm_id = d.hadm_id

GROUP BY 
  CASE 
    WHEN l.los < 8 THEN 'LOS < 8 days'
    ELSE 'LOS ≥ 8 days'
  END;