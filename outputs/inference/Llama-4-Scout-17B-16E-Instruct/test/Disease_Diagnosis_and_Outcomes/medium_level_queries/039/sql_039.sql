WITH 
  -- Identify AMI patients
  ami_patients AS (
    SELECT 
      a.subject_id,
      a.hadm_id,
      a.admittime,
      a.dischtime,
      a.deathtime,
      a.hospital_expire_flag,
      a.admission_type,
      p.anchor_age,
      p.gender
    FROM 
      `physionet-data.mimiciv_3_1_hosp.admissions` a
    JOIN 
      `physionet-data.mimiciv_3_1_hosp.patients` p
    ON 
      a.subject_id = p.subject_id
    WHERE 
      p.gender = 'F'
      AND p.anchor_age BETWEEN 66 AND 76
      AND EXISTS (
        SELECT 1
        FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
        JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` i
        ON d.icd_code = i.icd_code AND d.icd_version = i.icd_version
        WHERE d.subject_id = a.subject_id AND d.hadm_id = a.hadm_id
        AND i.long_title LIKE '%Acute myocardial infarction%'
      )
  ),
  
  -- Calculate LOS and time-to-death
  patient_data AS (
    SELECT 
      subject_id,
      hadm_id,
      admittime,
      dischtime,
      deathtime,  -- Explicitly select deathtime
      hospital_expire_flag,
      admission_type,
      anchor_age,
      gender,
      DATE_DIFF(dischtime, admittime, DAY) AS los,
      CASE 
        WHEN deathtime IS NOT NULL AND hospital_expire_flag = 1 THEN DATE_DIFF(deathtime, admittime, DAY)
        ELSE NULL
      END AS time_to_death
    FROM 
      ami_patients
  ),
  
  -- Categorize LOS and admission type
  categorized_data AS (
    SELECT 
      subject_id,
      hadm_id,
      los,
      time_to_death,
      hospital_expire_flag,
      admission_type,
      CASE 
        WHEN los BETWEEN 1 AND 3 THEN '1-3'
        WHEN los BETWEEN 4 AND 7 THEN '4-7'
        ELSE '>=8'
      END AS los_category,
      CASE 
        WHEN admission_type = 'Elective' THEN 'Non-emergent'
        ELSE 'Emergent'
      END AS admission_category
    FROM 
      patient_data
  )

-- Calculate mortality and median time-to-death
SELECT 
  los_category,
  admission_category,
  COUNT(CASE WHEN hospital_expire_flag = 1 THEN 1 END) AS deaths,
  COUNT(*) AS total_patients,
  APPROX_QUANTILES(time_to_death, 0.5) OVER () AS median_time_to_death
FROM 
  categorized_data
WHERE 
  los IS NOT NULL
GROUP BY 
  los_category,
  admission_category
ORDER BY 
  los_category,
  admission_category;