WITH 
  -- Filter patients and get hospitalization information
  patient_info AS (
    SELECT 
      p.subject_id,
      p.anchor_age,
      p.gender,
      a.hadm_id
    FROM 
      `physionet-data.mimiciv_3_1_hosp.patients` p
    JOIN 
      `physionet-data.mimiciv_3_1_hosp.admissions` a
    ON 
      p.subject_id = a.subject_id
    WHERE 
      p.gender = 'F'
      AND p.anchor_age BETWEEN 82 AND 92
  ),
  
  -- Identify cardiac procedures
  cardiac_procedures AS (
    SELECT 
      pi.hadm_id,
      COUNT(DISTINCT p.icd_code) AS num_cardiac_procedures
    FROM 
      `physionet-data.mimiciv_3_1_hosp.procedures_icd` p
    JOIN 
      `physionet-data.mimiciv_3_1_hosp.d_icd_procedures` dp
    ON 
      p.icd_code = dp.icd_code
      AND p.icd_version = dp.icd_version
    JOIN 
      patient_info pi
    ON 
      p.hadm_id = pi.hadm_id
    WHERE 
      LOWER(dp.long_title) LIKE '%cardiac%' 
      OR LOWER(dp.long_title) LIKE '%heart%'
    GROUP BY 
      pi.hadm_id
  )

-- Calculate the 25th percentile of distinct cardiac procedures per hospitalization
SELECT 
  PERCENTILE_CONT(0.25) WITHIN GROUP (ORDER BY num_cardiac_procedures) AS percentile_25
FROM 
  cardiac_procedures;