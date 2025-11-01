WITH 
  -- Identify male patients aged 76-86
  eligible_patients AS (
    SELECT subject_id
    FROM `physionet-data.mimiciv_3_1_hosp.patients`
    WHERE gender = 'M' AND anchor_age BETWEEN 76 AND 86
  ),
  
  -- Get hospitalizations for eligible patients
  eligible_admissions AS (
    SELECT hadm_id
    FROM `physionet-data.mimiciv_3_1_hosp.admissions`
    WHERE subject_id IN (SELECT subject_id FROM eligible_patients)
  ),
  
  -- Identify cardiac procedure codes (example: assume 'Cardiac' in description)
  cardiac_procedures AS (
    SELECT hadm_id, icd_code
    FROM `physionet-data.mimiciv_3_1_hosp.procedures_icd`
    JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_procedures` USING (icd_code, icd_version)
    WHERE hadm_id IN (SELECT hadm_id FROM eligible_admissions)
    AND LOWER(long_title) LIKE '%cardiac%'
  ),
  
  -- Count distinct cardiac procedure codes per hospitalization
  procedure_counts AS (
    SELECT hadm_id, COUNT(DISTINCT icd_code) AS distinct_procedure_count
    FROM cardiac_procedures
    GROUP BY hadm_id
  )

-- Calculate IQR of distinct procedure counts
SELECT 
  APPROX_QUANTILES(distinct_procedure_count, 25)[OFFSET(0)] AS Q1,
  APPROX_QUANTILES(distinct_procedure_count, 50)[OFFSET(0)] AS median,
  APPROX_QUANTILES(distinct_procedure_count, 75)[OFFSET(0)] AS Q3,
  APPROX_QUANTILES(distinct_procedure_count, 75)[OFFSET(0)] - 
  APPROX_QUANTILES(distinct_procedure_count, 25)[OFFSET(0)] AS IQR
FROM procedure_counts;