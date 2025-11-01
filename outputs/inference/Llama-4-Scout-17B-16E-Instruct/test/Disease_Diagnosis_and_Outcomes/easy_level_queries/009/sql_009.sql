WITH 
  -- Select patients with required information
  patients_info AS (
    SELECT 
      a.subject_id,
      a.hadm_id,
      a.admittime,
      a.dischtime,
      p.anchor_age,
      p.gender
    FROM 
      `physionet-data.mimiciv_3_1_hosp.admissions` a
    JOIN 
      `physionet-data.mimiciv_3_1_hosp.patients` p
    ON 
      a.subject_id = p.subject_id
  ),

  -- Filter patients with ischemic heart disease/ACS and COPD
  filtered_patients AS (
    SELECT 
      pi.subject_id,
      pi.hadm_id,
      pi.admittime,
      pi.dischtime,
      pi.anchor_age,
      pi.gender,
      DATE_DIFF(pi.dischtime, pi.admittime, DAY) AS hospital_los
    FROM 
      patients_info pi
    JOIN 
      `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` di
    ON 
      pi.hadm_id = di.hadm_id
    WHERE 
      pi.anchor_age BETWEEN 75 AND 85
      AND pi.gender = 'M'
      AND di.icd_version = 9 
      AND (di.icd_code IN (
        SELECT icd_code
        FROM `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses`
        WHERE icd_version = 9 AND long_title LIKE '%Acute ischemic heart disease%' 
           OR icd_code IN ('410', '411', '412', '413', '414')  
      ) OR di.icd_code IN (
        SELECT icd_code
        FROM `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses`
        WHERE icd_version = 9 AND long_title LIKE '%COPD%' 
           OR icd_code IN ('491', '492', '493', '494', '495', '496')  
      ))
  )

-- Calculate hospital LOS and determine 75th-percentile
SELECT 
  APPROX_QUANTILES(hospital_los, 100)[OFFSET(75)] AS los_75th_percentile
FROM 
  filtered_patients;