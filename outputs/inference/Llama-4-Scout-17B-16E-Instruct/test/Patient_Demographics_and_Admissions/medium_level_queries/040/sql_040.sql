WITH 
  -- Filter patients of interest
  patients_of_interest AS (
    SELECT 
      a.hadm_id,
      a.admittime,
      a.dischtime,
      a.discharge_location,
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
      AND p.anchor_age BETWEEN 70 AND 80
      AND a.admission_type = 'Surgical'
  ),

  -- Calculate LOS and categorize discharge outcomes
  patient_stays AS (
    SELECT 
      hadm_id,
      admittime,
      dischtime,
      discharge_location,
      hospital_expire_flag,
      TIMESTAMP_DIFF(dischtime, admittime, DAY) AS los_days,
      CASE 
        WHEN hospital_expire_flag = 1 THEN 'In-hospital death'
        WHEN discharge_location LIKE '%HOME%' THEN 'Home'
        ELSE 'Facility'
      END AS discharge_outcome
    FROM 
      patients_of_interest
  )

-- Stratify by LOS and discharge outcomes
SELECT 
  discharge_outcome,
  COUNT(CASE WHEN los_days >= 7 THEN hadm_id END) AS count_los_7,
  COUNT(CASE WHEN los_days >= 14 THEN hadm_id END) AS count_los_14,
  COUNT(hadm_id) AS total_patients
FROM 
  patient_stays
GROUP BY 
  discharge_outcome
ORDER BY 
  discharge_outcome;