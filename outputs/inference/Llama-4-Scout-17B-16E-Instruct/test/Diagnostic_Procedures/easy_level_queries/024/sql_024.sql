WITH 
  -- Filter for female patients aged 58-68
  eligible_patients AS (
    SELECT 
      a.subject_id, 
      a.hadm_id
    FROM 
      `physionet-data.mimiciv_3_1_hosp.admissions` a
    JOIN 
      `physionet-data.mimiciv_3_1_hosp.patients` p 
      ON a.subject_id = p.subject_id
    WHERE 
      p.gender = 'F' 
      AND p.anchor_age BETWEEN 58 AND 68
  ),

  -- Identify coronary angiography/PCI procedures
  procedures_of_interest AS (
    SELECT 
      pi.hadm_id,
      COUNT(DISTINCT pi.icd_code) AS num_procedures
    FROM 
      `physionet-data.mimiciv_3_1_hosp.procedures_icd` pi
    WHERE 
      pi.icd_code IN (
        SELECT 
          icd_code 
        FROM 
          `physionet-data.mimiciv_3_1_hosp.d_icd_procedures` 
        WHERE 
          long_title LIKE '%Coronary angiography%' 
          OR long_title LIKE '%Percutaneous transluminal coronary angioplasty%'
      )
    GROUP BY 
      pi.hadm_id
  )

-- Calculate the 75th percentile of distinct procedures
SELECT 
  APPROX_QUANTILES(num_procedures, 75) AS percentile_75
FROM (
  SELECT 
    num_procedures
  FROM 
    procedures_of_interest
  WHERE 
    hadm_id IN (SELECT hadm_id FROM eligible_patients)
);