WITH 
  -- Identify admissions for women aged 52-62 with AMI
  eligible_admissions AS (
    SELECT 
      a.hadm_id,
      a.subject_id,
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
      p.anchor_age BETWEEN 52 AND 62
      AND a.admission_type = 'AMI'
      AND p.gender = 'F'
  ),
  
  -- Find first Troponin T level for each admission
  first_troponin AS (
    SELECT 
      hadm_id,
      MIN(charttime) AS first_troponin_time,
      MIN(valuenum) AS first_troponin_value
    FROM 
      `physionet-data.mimiciv_3_1_hosp.labevents`
    WHERE 
      itemid = 4569  -- Troponin T
      AND valuenum > 0.01
    GROUP BY 
      hadm_id
  )

-- Combine information and calculate statistics
SELECT 
  COUNT(DISTINCT ea.hadm_id) AS admission_count,
  COUNT(DISTINCT ea.subject_id) AS patient_count,
  AVG(ea.anchor_age) AS mean_age,
  AVG(DATE_DIFF(ea.dischtime, ea.admittime, DAY)) AS mean_los,
  AVG(ft.first_troponin_value) AS mean_first_troponin,
  MIN(ft.first_troponin_value) AS min_first_troponin,
  MAX(ft.first_troponin_value) AS max_first_troponin,
  SUM(CASE WHEN ea.hospital_expire_flag = 1 OR ea.deathtime IS NOT NULL THEN 1 ELSE 0 END) AS in_hospital_deaths
FROM 
  eligible_admissions ea
JOIN 
  first_troponin ft
ON 
  ea.hadm_id = ft.hadm_id;