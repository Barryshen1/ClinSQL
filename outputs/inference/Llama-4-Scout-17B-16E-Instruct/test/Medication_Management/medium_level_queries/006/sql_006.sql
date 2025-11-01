WITH 
  -- Identify patients with T2DM and HF, aged 48-58
  eligible_patients AS (
    SELECT 
      a.subject_id,
      a.hadm_id,
      a.admittime,
      p.anchor_age
    FROM 
      `physionet-data.mimiciv_3_1_hosp.admissions` a
    JOIN 
      `physionet-data.mimiciv_3_1_hosp.patients` p 
        ON a.subject_id = p.subject_id
    WHERE 
      p.anchor_age BETWEEN 48 AND 58
      AND a.hadm_id IN (
        SELECT 
          hadm_id
        FROM 
          `physionet-data.mimiciv_3_1_hosp.diagnoses_icd`
        WHERE 
          icd_code IN ('250.0', '250.00', '250.01', '250.02', '250.03', '250.1', '250.10', '250.11', '250.12', '250.13', 
                       '402.0', '402.1', '402.9', '428.0', '428.1', '428.2', '428.3', '428.4', '428.9')
      )
      AND a.hadm_id IN (
        SELECT 
          hadm_id
        FROM 
          `physionet-data.mimiciv_3_1_hosp.diagnoses_icd`
        WHERE 
          icd_code IN ('250.0', '250.00', '250.01', '250.02', '250.03', '250.1', '250.10', '250.11', '250.12', '250.13')
      )
  ),
  
  -- Identify GLP-1 initiation
  glp1_initiation AS (
    SELECT 
      ep.subject_id,
      ep.hadm_id,
      p.starttime,
      CASE 
        WHEN p.starttime BETWEEN ep.admittime AND ep.admittime + INTERVAL 3 DAY THEN 'first_72h'
        WHEN p.starttime BETWEEN ep.admittime + INTERVAL 3 DAY - INTERVAL 2 DAY AND ep.admittime + INTERVAL 3 DAY THEN 'last_48h'
        ELSE 'other'
      END AS init_period
    FROM 
      eligible_patients ep
    JOIN 
      `physionet-data.mimiciv_3_1_hosp.prescriptions` p 
        ON ep.hadm_id = p.hadm_id
    WHERE 
      -- Assuming GLP-1s are coded specifically, e.g., 'Exenatide', 'Liraglutide'
      LOWER(p.drug) LIKE '%exenatide%' OR LOWER(p.drug) LIKE '%liraglutide%'
  )

SELECT 
  (COUNT(CASE WHEN init_period = 'first_72h' THEN hadm_id END) * 1.0 / COUNT(DISTINCT hadm_id)) * 100 AS rate_first_72h,
  (COUNT(CASE WHEN init_period = 'last_48h' THEN hadm_id END) * 1.0 / COUNT(DISTINCT hadm_id)) * 100 AS rate_last_48h,
  ((COUNT(CASE WHEN init_period = 'first_72h' THEN hadm_id END) * 1.0 / COUNT(DISTINCT hadm_id)) - 
   (COUNT(CASE WHEN init_period = 'last_48h' THEN hadm_id END) * 1.0 / COUNT(DISTINCT hadm_id))) * 100 AS rate_diff_pp
FROM 
  glp1_initiation;