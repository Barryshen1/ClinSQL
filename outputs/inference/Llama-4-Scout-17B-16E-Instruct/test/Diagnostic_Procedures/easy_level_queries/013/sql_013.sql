WITH 
  -- Filter patients of interest
  patients_of_interest AS (
    SELECT subject_id
    FROM `physionet-data.mimiciv_3_1_hosp.patients`
    WHERE gender = 'F' AND anchor_age BETWEEN 57 AND 67
  ),
  
  -- Identify hospitalizations for patients of interest
  hospitalizations AS (
    SELECT a.hadm_id
    FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
    JOIN patients_of_interest p ON a.subject_id = p.subject_id
  ),
  
  -- Identify valve repair/replacement procedures
  valve_procedures AS (
    SELECT p.hadm_id, p.icd_code
    FROM `physionet-data.mimiciv_3_1_hosp.procedures_icd` p
    JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_procedures` d ON p.icd_code = d.icd_code AND p.icd_version = d.icd_version
    WHERE d.long_title LIKE '%valve%' AND d.long_title IN ('Valve replacement, not otherwise specified', 
                                                             'Valve replacement, NOS', 
                                                             'Repair of aortic valve', 
                                                             'Repair of mitral valve', 
                                                             'Repair of tricuspid valve', 
                                                             'Repair of pulmonary valve', 
                                                             'Replacement of aortic valve', 
                                                             'Replacement of mitral valve', 
                                                             'Replacement of tricuspid valve', 
                                                             'Replacement of pulmonary valve')
  )

-- Count distinct valve procedures per hospitalization and find the minimum
SELECT MIN(distinct_procedures) AS min_distinct_valve_procedures
FROM (
  SELECT hadm_id, COUNT(DISTINCT icd_code) AS distinct_procedures
  FROM valve_procedures
  GROUP BY hadm_id
);