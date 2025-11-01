WITH 
-- Identify patients with T2DM and heart failure
patient_selection AS (
  SELECT DISTINCT p.subject_id, a.hadm_id, a.admittime, a.dischtime
  FROM `physionet-data.mimiciv_3_1_hosp.patients` p
  JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a ON p.subject_id = a.subject_id
  JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` diag ON a.subject_id = diag.subject_id AND a.hadm_id = diag.hadm_id
  JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` d_diag ON diag.icd_code = d_diag.icd_code AND diag.icd_version = d_diag.icd_version
  WHERE p.gender = 'M' AND p.anchor_age BETWEEN 36 AND 46
  AND d_diag.long_title LIKE '%Diabetes mellitus type 2%'  
  AND EXISTS (
    SELECT 1
    FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` diag_hf
    JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` d_diag_hf ON diag_hf.icd_code = d_diag_hf.icd_code AND diag_hf.icd_version = d_diag_hf.icd_version
    WHERE diag_hf.subject_id = a.subject_id AND diag_hf.hadm_id = a.hadm_id
    AND (d_diag_hf.long_title LIKE '%Heart failure%' OR d_diag_hf.long_title LIKE '%Cardiac failure%')
  )
),

-- Analyze antidiabetic medication in the first 12 hours and last 48 hours
medication_analysis AS (
  SELECT ps.subject_id, ps.hadm_id,
         SUM(CASE WHEN p.starttime BETWEEN ps.admittime AND (ps.admittime + INTERVAL 12 HOUR) THEN 1 ELSE 0 END) AS med_start_12h,
         SUM(CASE WHEN p.starttime BETWEEN (ps.dischtime - INTERVAL 48 HOUR) AND ps.dischtime THEN 1 ELSE 0 END) AS med_end_48h
  FROM patient_selection ps
  JOIN `physionet-data.mimiciv_3_1_hosp.prescriptions` p ON ps.subject_id = p.subject_id AND ps.hadm_id = p.hadm_id
  WHERE LOWER(p.drug) LIKE '%metformin%' OR LOWER(p.drug) LIKE '%sulfonylurea%'  
  GROUP BY ps.subject_id, ps.hadm_id
)

-- Calculate initiation rates and net change
SELECT 
  COUNT(CASE WHEN med_start_12h > 0 THEN 1 END) AS init_count_start_12h,
  COUNT(CASE WHEN med_end_48h > 0 THEN 1 END) AS init_count_end_48h,
  COUNT(*) AS total_count,
  CASE 
    WHEN COUNT(*) = 0 THEN NULL 
    ELSE COUNT(CASE WHEN med_start_12h > 0 THEN 1 END) / COUNT(*) 
  END AS init_rate_start_12h,
  CASE 
    WHEN COUNT(*) = 0 THEN NULL 
    ELSE COUNT(CASE WHEN med_end_48h > 0 THEN 1 END) / COUNT(*) 
  END AS init_rate_end_48h,
  CASE 
    WHEN COUNT(*) = 0 THEN NULL 
    ELSE (COUNT(CASE WHEN med_end_48h > 0 THEN 1 END) / COUNT(*)) - (COUNT(CASE WHEN med_start_12h > 0 THEN 1 END) / COUNT(*)) 
  END AS net_change
FROM medication_analysis;