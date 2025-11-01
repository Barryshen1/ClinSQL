WITH 
  -- Identify ACS admissions
  acs_admissions AS (
    SELECT 
      a.hadm_id,
      a.subject_id,
      a.admittime,
      a.dischtime,
      EXTRACT(DAY FROM a.dischtime - a.admittime) AS los
    FROM 
      `physionet-data.mimiciv_3_1_hosp.admissions` a
    JOIN 
      `physionet-data.mimiciv_3_1_hosp.patients` p ON a.subject_id = p.subject_id
    JOIN 
      `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d ON a.hadm_id = d.hadm_id
    JOIN 
      `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` dd ON d.icd_code = dd.icd_code AND d.icd_version = dd.icd_version
    WHERE 
      p.gender = 'M'
      AND p.anchor_age BETWEEN 35 AND 45
      AND dd.long_title LIKE '%Acute coronary syndrome%'
  ),
  
  -- Identify ultrasound procedures
  ultrasound_procedures AS (
    SELECT 
      hadm_id,
      COUNT(*) AS ultrasound_count
    FROM 
      `physionet-data.mimiciv_3_1_hosp.procedures_icd` p
    JOIN 
      `physionet-data.mimiciv_3_1_hosp.d_icd_procedures` dp ON p.icd_code = dp.icd_code AND p.icd_version = dp.icd_version
    WHERE 
      dp.long_title LIKE '%Ultrasound%'
      OR dp.long_title LIKE '%Echocardiography%'
    GROUP BY 
      hadm_id
  )

SELECT 
  CASE 
    WHEN los BETWEEN 1 AND 3 THEN '1-3 days'
    WHEN los BETWEEN 4 AND 7 THEN '4-7 days'
  END AS los_category,
  COUNT(DISTINCT aa.subject_id) AS patient_count,
  AVG(ultrasound_count) AS mean_ultrasound_per_admission
FROM 
  acs_admissions aa
LEFT JOIN 
  ultrasound_procedures up ON aa.hadm_id = up.hadm_id
GROUP BY 
  CASE 
    WHEN los BETWEEN 1 AND 3 THEN '1-3 days'
    WHEN los BETWEEN 4 AND 7 THEN '4-7 days'
  END
ORDER BY 
  los_category;