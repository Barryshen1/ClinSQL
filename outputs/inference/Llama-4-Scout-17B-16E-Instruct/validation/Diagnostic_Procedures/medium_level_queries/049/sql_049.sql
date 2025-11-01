WITH 
  -- Identify sepsis patients without septic shock
  sepsis_patients AS (
    SELECT 
      a.subject_id, 
      a.hadm_id, 
      a.admittime, 
      a.dischtime
    FROM 
      `physionet-data.mimiciv_3_1_hosp.admissions` a
    JOIN 
      `physionet-data.mimiciv_3_1_hosp.patients` p 
      ON a.subject_id = p.subject_id
    WHERE 
      p.anchor_age BETWEEN 87 AND 97 
      AND p.gender = 'M'
      AND a.hadm_id IN (
        SELECT 
          hadm_id 
        FROM 
          `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` 
        WHERE 
          icd_code LIKE '%sepsis%' 
          OR icd_code LIKE '%septic%'
      )
      AND a.hadm_id NOT IN (
        SELECT 
          hadm_id 
        FROM 
          `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` 
        WHERE 
          icd_code LIKE '%septic shock%'
      )
  ),
  
  -- Calculate admission duration and group by duration
  admission_durations AS (
    SELECT 
      hadm_id, 
      admittime, 
      dischtime,
      CASE 
        WHEN TIMESTAMP_DIFF(dischtime, admittime, DAY) BETWEEN 1 AND 3 THEN '1-3 days'
        WHEN TIMESTAMP_DIFF(dischtime, admittime, DAY) BETWEEN 4 AND 7 THEN '4-7 days'
        ELSE 'other'
      END AS duration_group
    FROM 
      sepsis_patients
  ),
  
  -- Count diagnostic procedures for each admission
  procedures_per_admission AS (
    SELECT 
      hadm_id, 
      COUNT(icd_code) AS num_procedures
    FROM 
      `physionet-data.mimiciv_3_1_hosp.procedures_icd`
    GROUP BY 
      hadm_id
  )

-- Calculate mean diagnostic procedures for each duration group
SELECT 
  duration_group, 
  AVG(num_procedures) AS mean_procedures
FROM 
  admission_durations
  JOIN procedures_per_admission 
    ON admission_durations.hadm_id = procedures_per_admission.hadm_id
WHERE 
  duration_group IN ('1-3 days', '4-7 days')
GROUP BY 
  duration_group;