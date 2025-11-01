WITH 
  -- Identify patients with sepsis (ICD-9: 995.91, ICD-10: A40.0, A41.0, R65.1)
  sepsis_patients AS (
    SELECT 
      a.subject_id, 
      a.hadm_id, 
      a.admittime, 
      a.dischtime, 
      a.deathtime,
      a.hospital_expire_flag,
      p.anchor_age,
      p.gender
    FROM 
      `physionet-data.mimiciv_3_1_hosp.admissions` a
    JOIN 
      `physionet-data.mimiciv_3_1_hosp.patients` p 
        ON a.subject_id = p.subject_id
    JOIN 
      `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d 
        ON a.hadm_id = d.hadm_id
    WHERE 
      p.gender = 'M' 
      AND p.anchor_age BETWEEN 50 AND 60
      AND (d.icd_code IN ('995.91', 'A40.0', 'A41.0', 'R65.1') 
           OR (d.icd_code LIKE ' sepsis%' AND d.icd_version = 10))
  ),
  
  -- Calculate hospital mortality and LOS
  patient_outcomes AS (
    SELECT 
      subject_id, 
      hadm_id, 
      admittime,
      dischtime,
      deathtime,
      hospital_expire_flag,
      TIMESTAMP_DIFF(COALESCE(dischtime, deathtime), admittime, DAY) AS los
    FROM 
      sepsis_patients
  ),
  
  -- Day-1 ICU status (Simplified: just check if icustay exists and started within 24hrs of admission)
  icu_status AS (
    SELECT 
      subject_id, 
      hadm_id,
      MIN(intime) AS icu_admit_time
    FROM 
      `physionet-data.mimiciv_3_1_icu.icustays`
    GROUP BY 
      subject_id, 
      hadm_id
  )

SELECT 
  -- Mortality by LOS strata
  CASE 
    WHEN los <= 7 THEN 'LOS ≤7 days'
    ELSE 'LOS >7 days'
  END AS los_strata,
  COUNT(DISTINCT CASE WHEN hospital_expire_flag = 1 OR deathtime IS NOT NULL THEN hadm_id END) AS num_deaths,
  COUNT(DISTINCT hadm_id) AS total_patients,
  COUNT(DISTINCT CASE WHEN icu_admit_time IS NOT NULL AND TIMESTAMP_DIFF(icu_admit_time, admittime, DAY) = 0 THEN hadm_id END) AS icu_on_day1
FROM 
  patient_outcomes po
LEFT JOIN 
  icu_status ic 
    ON po.hadm_id = ic.hadm_id
GROUP BY 
  1
ORDER BY 
  1;