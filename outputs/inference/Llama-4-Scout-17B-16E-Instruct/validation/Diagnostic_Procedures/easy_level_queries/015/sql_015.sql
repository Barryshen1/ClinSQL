WITH 
  -- Identify CABG procedures
  cabg_procedures AS (
    SELECT icd_code
    FROM `physionet-data.mimiciv_3_1_hosp.d_icd_procedures`
    WHERE long_title LIKE '%CABG%'
  ),
  
  -- Identify patients of interest
  patients_of_interest AS (
    SELECT subject_id
    FROM `physionet-data.mimiciv_3_1_hosp.patients`
    WHERE gender = 'M' AND anchor_age BETWEEN 45 AND 55
  ),
  
  -- Count distinct CABG procedures per patient
  patient_cabg_count AS (
    SELECT 
      p.subject_id,
      COUNT(DISTINCT pi.icd_code) AS cabg_count
    FROM `physionet-data.mimiciv_3_1_hosp.patients` p
    JOIN patients_of_interest poi ON p.subject_id = poi.subject_id
    JOIN `physionet-data.mimiciv_3_1_hosp.procedures_icd` pi ON p.subject_id = pi.subject_id
    JOIN cabg_procedures cp ON pi.icd_code = cp.icd_code
    GROUP BY p.subject_id
  )

-- Calculate the 25th percentile of CABG counts
SELECT 
  APPROX_QUANTILES(cabg_count, 25) AS percentile_25
FROM patient_cabg_count;