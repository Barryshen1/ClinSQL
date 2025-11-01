WITH cohort AS (
  SELECT 
    p.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    DATE_DIFF(a.dischtime, a.admittime, DAY) AS los_days,
    diag.seq_num,
    -- Classify diagnosis as primary (seq_num=1) or secondary (seq_num>1)
    CASE WHEN diag.seq_num = 1 THEN 'Primary' ELSE 'Secondary' END AS diagnosis_type
  FROM `physionet-data.mimiciv_3_1_hosp.patients` p
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a
    ON p.subject_id = a.subject_id
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` diag
    ON a.hadm_id = diag.hadm_id
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` d
    ON diag.icd_code = d.icd_code AND diag.icd_version = d.icd_version
  WHERE 
    p.gender = 'M'
    AND p.anchor_age BETWEEN 51 AND 61
    AND d.long_title LIKE 'Acute pancreatitis%'
),
-- Count radiography/CT procedures per admission
proc_counts AS (
  SELECT 
    p.hadm_id,
    COUNT(DISTINCT p.icd_code) AS num_procedures  -- Count distinct procedures to avoid duplicates
  FROM `physionet-data.mimiciv_3_1_hosp.procedures_icd` p
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_procedures` d
    ON p.icd_code = d.icd_code AND p.icd_version = d.icd_version
  WHERE 
    -- ICD-10 PCS codes for radiography/CT (abdominal)
    (d.icd_code LIKE 'BW2%' OR d.icd_code LIKE 'BW3%' OR d.icd_code LIKE 'BW4%')
  GROUP BY p.hadm_id
)
SELECT 
  c.diagnosis_type,
  CASE 
    WHEN c.los_days BETWEEN 1 AND 3 THEN '1-3'
    WHEN c.los_days BETWEEN 4 AND 7 THEN '4-7'
    ELSE 'Other' 
  END AS los_group,
  COUNT(DISTINCT c.hadm_id) AS admission_count,
  COUNT(DISTINCT c.subject_id) AS patient_count,
  COALESCE(AVG(p.num_procedures), 0) AS mean_procedures_per_admission
FROM cohort c
LEFT JOIN proc_counts p
  ON c.hadm_id = p.hadm_id
WHERE c.los_days BETWEEN 1 AND 7  -- Filter to only LOS 1-7 days
GROUP BY diagnosis_type, los_group
ORDER BY diagnosis_type, los_group;