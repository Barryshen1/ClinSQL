WITH patient_admissions AS (
  SELECT 
    a.hadm_id,
    p.subject_id,
    p.gender,
    p.anchor_age + (EXTRACT(YEAR FROM a.admittime) - p.anchor_year) AS age_at_admission,
    DATETIME_DIFF(a.dischtime, a.admittime, DAY) AS duration_days
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON a.subject_id = p.subject_id
  WHERE a.dischtime IS NOT NULL
    AND p.gender = 'M'
),
sepsis_admissions AS (
  SELECT 
    hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd`
  WHERE icd_version = 10
    AND (icd_code LIKE 'A40%' OR icd_code LIKE 'A41%')
  GROUP BY hadm_id
),
non_shock_admissions AS (
  SELECT 
    hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd`
  WHERE icd_version = 10
    AND icd_code = 'R6521'
  GROUP BY hadm_id
),
sepsis_no_shock AS (
  SELECT sa.hadm_id
  FROM sepsis_admissions sa
  LEFT JOIN non_shock_admissions nsa
    ON sa.hadm_id = nsa.hadm_id
  WHERE nsa.hadm_id IS NULL
),
target_admissions AS (
  SELECT 
    pa.hadm_id,
    pa.duration_days,
    CASE 
      WHEN pa.duration_days BETWEEN 1 AND 3 THEN '1-3 days'
      WHEN pa.duration_days BETWEEN 4 AND 7 THEN '4-7 days'
    END AS duration_group
  FROM patient_admissions pa
  INNER JOIN sepsis_no_shock sns
    ON pa.hadm_id = sns.hadm_id
  WHERE pa.age_at_admission BETWEEN 87 AND 97
    AND pa.duration_days BETWEEN 1 AND 7
),
diagnostic_procedures AS (
  SELECT 
    p.hadm_id,
    COUNT(*) AS diag_proc_count
  FROM `physionet-data.mimiciv_3_1_hosp.procedures_icd` p
  WHERE p.icd_version = 10
    AND SUBSTR(p.icd_code, 1, 1) IN ('B', 'C')
  GROUP BY p.hadm_id
)
SELECT 
  ta.duration_group,
  AVG(COALESCE(dp.diag_proc_count, 0)) AS mean_diagnostic_procedures
FROM target_admissions ta
LEFT JOIN diagnostic_procedures dp
  ON ta.hadm_id = dp.hadm_id
GROUP BY ta.duration_group
ORDER BY 
  CASE ta.duration_group
    WHEN '1-3 days' THEN 1
    WHEN '4-7 days' THEN 2
  END;