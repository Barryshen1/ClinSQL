WITH cohort AS (
  SELECT DISTINCT p.subject_id
  FROM `physionet-data.mimiciv_3_1_hosp`.patients p
  INNER JOIN `physionet-data.mimiciv_3_1_hosp`.admissions a
    ON p.subject_id = a.subject_id
  WHERE p.gender = 'F'
    AND (p.anchor_age + (EXTRACT(YEAR FROM a.admittime) - p.anchor_year)) BETWEEN 64 AND 74
),
target_procs AS (
  SELECT icd_code, icd_version
  FROM `physionet-data.mimiciv_3_1_hosp`.d_icd_procedures
  WHERE LOWER(long_title) LIKE '%cardiac catheterization%'
    AND LOWER(long_title) LIKE '%diagnostic%'
),
patient_proc_counts AS (
  SELECT 
    c.subject_id,
    COUNT(pri.icd_code) AS proc_count
  FROM cohort c
  LEFT JOIN `physionet-data.mimiciv_3_1_hosp`.admissions a
    ON c.subject_id = a.subject_id
  LEFT JOIN `physionet-data.mimiciv_3_1_hosp`.procedures_icd pri
    ON a.hadm_id = pri.hadm_id
  LEFT JOIN target_procs tp
    ON pri.icd_code = tp.icd_code AND pri.icd_version = tp.icd_version
  WHERE (c.subject_id IS NULL OR 
         (a.admittime IS NOT NULL AND 
          (SELECT p.anchor_age + (EXTRACT(YEAR FROM a.admittime) - p.anchor_year)
           FROM `physionet-data.mimiciv_3_1_hosp`.patients p
           WHERE p.subject_id = c.subject_id) BETWEEN 64 AND 74))
  GROUP BY c.subject_id
)
SELECT MIN(proc_count) AS min_procedures_per_patient
FROM patient_proc_counts;