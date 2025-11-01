WITH 
  -- Identify ischemic stroke cases
  ischemic_stroke AS (
    SELECT 
      di.subject_id,
      di.hadm_id,
      di.seq_num,
      ddd.long_title AS diagnosis
    FROM 
      `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` di
    JOIN 
      `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` ddd 
      ON di.icd_code = ddd.icd_code AND di.icd_version = ddd.icd_version
    WHERE 
      (di.icd_code LIKE '433%' OR di.icd_code LIKE 'I63%')  -- Ischemic stroke ICD codes
  ),
  
  -- Identify procedures
  procedures AS (
    SELECT 
      p.hadm_id,
      COUNT(p.seq_num) as num_procedures
    FROM 
      `physionet-data.mimiciv_3_1_hosp.procedures_icd` p
    GROUP BY 
      p.hadm_id
  ),
  
  -- Patient demographics and admission details
  patient_admissions AS (
    SELECT 
      a.hadm_id,
      p.subject_id,
      p.gender,
      p.anchor_age,
      a.admittime,
      a.dischtime
    FROM 
      `physionet-data.mimiciv_3_1_hosp.admissions` a
    JOIN 
      `physionet-data.mimiciv_3_1_hosp.patients` p 
      ON a.subject_id = p.subject_id
    WHERE 
      p.gender = 'F' AND p.anchor_age BETWEEN 49 AND 59
  )

-- Final query
SELECT 
  CASE 
    WHEN (pa.dischtime - pa.admittime) BETWEEN INTERVAL 1 DAY AND INTERVAL 4 DAY THEN '1-4 days'
    WHEN (pa.dischtime - pa.admittime) BETWEEN INTERVAL 5 DAY AND INTERVAL 8 DAY THEN '5-8 days'
  END AS stay_duration,
  COUNT(DISTINCT pr.hadm_id) AS num_admissions,
  AVG(pr.num_procedures) AS mean_procedures,
  MIN(pr.num_procedures) AS min_procedures,
  MAX(pr.num_procedures) AS max_procedures
FROM 
  patient_admissions pa
LEFT JOIN 
  procedures pr ON pa.hadm_id = pr.hadm_id
WHERE 
  (pa.dischtime - pa.admittime) BETWEEN INTERVAL 1 DAY AND INTERVAL 8 DAY
GROUP BY 
  stay_duration
;