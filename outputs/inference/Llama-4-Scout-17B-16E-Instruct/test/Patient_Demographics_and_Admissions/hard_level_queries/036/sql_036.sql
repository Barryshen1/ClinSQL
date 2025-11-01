WITH 
  -- Define acute pancreatitis ICD codes (example codes, might need adjustment)
  acute_pancreatitis_icd AS (
    SELECT icd_code
    FROM `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses`
    WHERE long_title LIKE '%Acute pancreatitis%'
  ),
  
  -- Identify target patients and admissions
  target_admissions AS (
    SELECT a.hadm_id, a.subject_id
    FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
    JOIN `physionet-data.mimiciv_3_1_hosp.patients` p 
      ON a.subject_id = p.subject_id
    WHERE p.gender = 'F'
      AND p.anchor_age BETWEEN 72 AND 82
      AND a.insurance = 'Medicare'
      AND a.admission_type = 'Emergency'
      AND a.discharge_location NOT IN (SELECT admission_location FROM `physionet-data.mimiciv_3_1_hosp.admissions`)
      AND a.hadm_id IN (
        SELECT hadm_id
        FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd`
        WHERE icd_code IN (SELECT icd_code FROM acute_pancreatitis_icd)
        AND seq_num = 1  -- Principal diagnosis
      )
  )

SELECT COUNT(DISTINCT hadm_id) AS total_admissions
FROM target_admissions;