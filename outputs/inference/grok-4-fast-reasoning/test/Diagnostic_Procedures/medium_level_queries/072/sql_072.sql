WITH patients_female_age AS (
  SELECT subject_id
  FROM `physionet-data.mimiciv_3_1_hosp.patients`
  WHERE gender = 'F' AND anchor_age BETWEEN 52 AND 62
),
admissions_cohort AS (
  SELECT a.subject_id, a.hadm_id, a.admittime, a.dischtime,
         TIMESTAMP_DIFF(a.dischtime, a.admittime, DAY) AS los_days
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  INNER JOIN patients_female_age p ON a.subject_id = p.subject_id
  WHERE a.hadm_id IS NOT NULL
),
pancreatitis_flags AS (
  SELECT di.hadm_id,
         MAX(CASE WHEN di.seq_num = 1 
                  AND ((di.icd_version = '9' AND di.icd_code = '577.0') 
                       OR (di.icd_version = '10' AND di.icd_code LIKE 'K85%'))
                  THEN 1 ELSE 0 END) AS has_primary_pancreatitis,
         MAX(CASE WHEN (di.icd_version = '9' AND di.icd_code = '577.0') 
                       OR (di.icd_version = '10' AND di.icd_code LIKE 'K85%')
                  THEN 1 ELSE 0 END) AS has_pancreatitis
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` di
  GROUP BY di.hadm_id
),
pancreatitis_admissions AS (
  SELECT pf.hadm_id, ac.los_days,
         CASE WHEN pf.has_primary_pancreatitis = 1 THEN 'primary' ELSE 'secondary' END AS diag_type
  FROM pancreatitis_flags pf
  INNER JOIN admissions_cohort ac ON pf.hadm_id = ac.hadm_id
  WHERE pf.has_pancreatitis = 1
),
diagnostic_procedure_counts AS (
  SELECT pi.hadm_id, COUNT(*) AS num_diagnostic_procedures
  FROM `physionet-data.mimiciv_3_1_hosp.procedures_icd` pi
  WHERE (pi.icd_version = '9' AND pi.icd_code BETWEEN '87000' AND '89999')
     OR (pi.icd_version = '10' AND pi.icd_code LIKE 'B%')
  GROUP BY pi.hadm_id
)
SELECT 
  CASE WHEN pa.los_days <= 4 THEN '1-4' ELSE '5-8' END AS los_group,
  pa.diag_type,
  AVG(COALESCE(dpc.num_diagnostic_procedures, 0)) AS mean_procedures,
  MIN(COALESCE(dpc.num_diagnostic_procedures, 0)) AS min_procedures,
  MAX(COALESCE(dpc.num_diagnostic_procedures, 0)) AS max_procedures,
  COUNT(*) AS num_admissions  -- Optional: for context
FROM pancreatitis_admissions pa
LEFT JOIN diagnostic_procedure_counts dpc ON pa.hadm_id = dpc.hadm_id
WHERE pa.los_days BETWEEN 1 AND 8
GROUP BY 
  CASE WHEN pa.los_days <= 4 THEN '1-4' ELSE '5-8' END,
  pa.diag_type
ORDER BY los_group, diag_type;