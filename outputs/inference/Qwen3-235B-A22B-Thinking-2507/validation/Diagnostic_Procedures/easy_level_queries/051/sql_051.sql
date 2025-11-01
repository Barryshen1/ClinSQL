WITH cohort AS (
  SELECT 
    p.subject_id,
    a.hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.patients` p
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a
    ON p.subject_id = a.subject_id
  WHERE p.gender = 'M'
    AND (p.anchor_age + (EXTRACT(YEAR FROM a.admittime) - p.anchor_year)) BETWEEN 41 AND 51
),
ecg_telem_codes AS (
  SELECT 
    icd_code, 
    icd_version
  FROM `physionet-data.mimiciv_3_1_hosp.d_icd_procedures`
  WHERE 
    LOWER(long_title) LIKE '%ecg%'
    OR LOWER(long_title) LIKE '%ekg%'
    OR LOWER(long_title) LIKE '%electrocardiogram%'
    OR LOWER(long_title) LIKE '%telemetry%'
    OR LOWER(long_title) LIKE '%cardiac monitoring%'
),
patient_proc_counts AS (
  SELECT
    c.subject_id,
    COUNT(DISTINCT CASE 
      WHEN e.icd_code IS NOT NULL THEN CONCAT(p.icd_code, '_', p.icd_version) 
    END) AS proc_count
  FROM cohort c
  LEFT JOIN `physionet-data.mimiciv_3_1_hosp.procedures_icd` p
    ON c.subject_id = p.subject_id 
    AND c.hadm_id = p.hadm_id
  LEFT JOIN ecg_telem_codes e
    ON p.icd_code = e.icd_code 
    AND p.icd_version = e.icd_version
  GROUP BY c.subject_id
)
SELECT
  PERCENTILE_CONT(proc_count, 0.75) OVER() AS p75
FROM patient_proc_counts
LIMIT 1;