WITH eligible_admissions AS (
  SELECT 
    a.subject_id,
    a.hadm_id,
    a.admittime,
    p.anchor_year,
    EXTRACT(YEAR FROM a.admittime) - p.anchor_year AS age_at_admission
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` p 
    ON a.subject_id = p.subject_id
  WHERE p.gender = 'M'
    AND EXTRACT(YEAR FROM a.admittime) - p.anchor_year BETWEEN 75 AND 85
),
relevant_procedures AS (
  SELECT 
    pi.subject_id,
    pi.hadm_id,
    pi.icd_code
  FROM `physionet-data.mimiciv_3_1_hosp.procedures_icd` pi
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_procedures` dpi 
    ON pi.icd_code = dpi.icd_code AND pi.icd_version = dpi.icd_version
  WHERE LOWER(dpi.long_title) LIKE '%ablation%' 
     OR LOWER(dpi.long_title) LIKE '%cardioversion%'
),
patient_procedures AS (
  SELECT 
    ea.subject_id,
    rp.icd_code
  FROM eligible_admissions ea
  LEFT JOIN relevant_procedures rp 
    ON ea.subject_id = rp.subject_id AND ea.hadm_id = rp.hadm_id
),
patient_counts AS (
  SELECT 
    subject_id,
    COUNT(DISTINCT icd_code) AS num_procedures
  FROM patient_procedures
  GROUP BY subject_id
),
percentiles AS (
  SELECT
    PERCENTILE_CONT(0.75) WITHIN GROUP (ORDER BY num_procedures) AS p75,
    PERCENTILE_CONT(0.25) WITHIN GROUP (ORDER BY num_procedures) AS p25
  FROM patient_counts
)
SELECT 
  p75 - p25 AS iqr
FROM percentiles;