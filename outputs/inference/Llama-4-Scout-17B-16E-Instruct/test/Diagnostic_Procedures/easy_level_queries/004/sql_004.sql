WITH 
  -- Identify CABG procedure codes (ICD-9: 36.01-36.09, ICD-10: 335.0, 335.1, 335.2)
  cabg_procedures AS (
    SELECT icd_code, icd_version
    FROM `physionet-data.mimiciv_3_1_hosp.d_icd_procedures`
    WHERE icd_version = 9 AND icd_code BETWEEN '36.01' AND '36.09'
    UNION ALL
    SELECT icd_code, icd_version
    FROM `physionet-data.mimiciv_3_1_hosp.d_icd_procedures`
    WHERE icd_version = 10 AND icd_code IN ('335.0', '335.1', '335.2')
  ),

  -- Identify patients of interest (females, aged 41-51)
  patients_of_interest AS (
    SELECT subject_id
    FROM `physionet-data.mimiciv_3_1_hosp.patients`
    WHERE gender = 'F' AND anchor_age BETWEEN 41 AND 51
  ),

  -- Count distinct CABG procedures per patient
  patient_cabg_counts AS (
    SELECT 
      p.subject_id,
      COUNT(DISTINCT pi.icd_code) AS cabg_count
    FROM `physionet-data.mimiciv_3_1_hosp.procedures_icd` pi
    JOIN patients_of_interest p ON pi.subject_id = p.subject_id
    JOIN cabg_procedures cp ON pi.icd_code = cp.icd_code AND pi.icd_version = cp.icd_version
    GROUP BY p.subject_id
  )

-- Calculate standard deviation of CABG counts
SELECT 
  stddev(cabg_count) AS std_dev_cabg_procedures
FROM patient_cabg_counts;