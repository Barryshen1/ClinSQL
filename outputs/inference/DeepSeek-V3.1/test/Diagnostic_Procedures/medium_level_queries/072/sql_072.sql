WITH cohort AS (
  SELECT 
    adm.subject_id, 
    adm.hadm_id, 
    DATE_DIFF(adm.dischtime, adm.admittime, DAY) AS los_days,
    -- Classify LOS group
    CASE 
      WHEN DATE_DIFF(adm.dischtime, adm.admittime, DAY) BETWEEN 1 AND 4 THEN '1-4'
      WHEN DATE_DIFF(adm.dischtime, adm.admittime, DAY) BETWEEN 5 AND 8 THEN '5-8'
    END AS los_group,
    -- Primary vs secondary diagnosis for pancreatitis
    CASE 
      WHEN diag.seq_num = 1 THEN 'Primary'
      ELSE 'Secondary'
    END AS diagnosis_type
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` adm
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` pat
    ON adm.subject_id = pat.subject_id
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` diag
    ON adm.hadm_id = diag.hadm_id
  WHERE 
    pat.gender = 'F'
    AND pat.anchor_age BETWEEN 52 AND 62
    AND (
      (diag.icd_code = '577.0' AND diag.icd_version = 9) OR
      (diag.icd_code = 'K85' AND diag.icd_version = 10)
    )
    AND DATE_DIFF(adm.dischtime, adm.admittime, DAY) BETWEEN 1 AND 8
),
-- Count procedures per admission
proc_counts AS (
  SELECT 
    c.subject_id,
    c.hadm_id,
    c.los_group,
    c.diagnosis_type,
    COUNT(DISTINCT proc.icd_code) AS num_procedures
  FROM cohort c
  LEFT JOIN `physionet-data.mimiciv_3_1_hosp.procedures_icd` proc
    ON c.hadm_id = proc.hadm_id
  GROUP BY c.subject_id, c.hadm_id, c.los_group, c.diagnosis_type
)
-- Aggregate by LOS group and diagnosis type
SELECT 
  los_group,
  diagnosis_type,
  COUNT(*) AS num_admissions,
  AVG(num_procedures) AS mean_procedures,
  MIN(num_procedures) AS min_procedures,
  MAX(num_procedures) AS max_procedures
FROM proc_counts
GROUP BY los_group, diagnosis_type
ORDER BY los_group, diagnosis_type;