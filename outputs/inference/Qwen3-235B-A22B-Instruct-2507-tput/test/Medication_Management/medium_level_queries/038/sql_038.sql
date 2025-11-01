WITH patient_cohort AS (
  SELECT DISTINCT a.hadm_id, a.subject_id, a.admittime, a.dischtime
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` p ON a.subject_id = p.subject_id
  WHERE p.gender = 'M'
    AND EXTRACT(YEAR FROM a.admittime) - p.anchor_year + p.anchor_age BETWEEN 57 AND 67
),
diabetes_hf_cohort AS (
  -- Ensure each hadm_id has at least one diabetes and one acute HF diagnosis
  SELECT pc.hadm_id
  FROM patient_cohort pc
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` di ON pc.hadm_id = di.hadm_id
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` d ON di.icd_code = d.icd_code AND di.icd_version = d.icd_version
  GROUP BY pc.hadm_id
  HAVING 
    SUM(CASE WHEN LOWER(d.long_title) LIKE '%diabetes%' THEN 1 ELSE 0 END) >= 1
    AND SUM(CASE 
      WHEN LOWER(d.long_title) LIKE '%heart failure%' AND (LOWER(d.long_title) LIKE '%acute%' OR d.icd_code LIKE 'I50.%') THEN 1 
      ELSE 0 
    END) >= 1
),
glp1_prescriptions AS (
  SELECT p.hadm_id,
         p.starttime,
         CASE 
           WHEN p.starttime BETWEEN adm.admittime AND DATETIME_ADD(adm.admittime, INTERVAL 72 HOUR)
             THEN 'first_72h'
           WHEN p.starttime >= DATETIME_SUB(adm.dischtime, INTERVAL 24 HOUR) AND p.starttime <= adm.dischtime
             THEN 'final_24h'
         END AS time_window
  FROM `physionet-data.mimiciv_3_1_hosp.prescriptions` p
  INNER JOIN diabetes_hf_cohort dh ON p.hadm_id = dh.hadm_id
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` adm ON p.hadm_id = adm.hadm_id
  WHERE LOWER(p.drug) IN (
    'exenatide', 'liraglutide', 'semaglutide',
    'byetta', 'victoza', 'ozempic', 'rybelsus', 'saxenda'
  )
    AND p.starttime IS NOT NULL
),
cohort_stats AS (
  SELECT 
    COUNT(DISTINCT dh.hadm_id) AS total_patients,
    COUNT(DISTINCT CASE WHEN gp.time_window = 'first_72h' THEN gp.hadm_id END) AS initiated_first_72h,
    COUNT(DISTINCT CASE WHEN gp.time_window = 'final_24h' THEN gp.hadm_id END) AS initiated_final_24h,
    COUNT(DISTINCT gp.hadm_id) AS any_glp1_use
  FROM diabetes_hf_cohort dh
  LEFT JOIN glp1_prescriptions gp ON dh.hadm_id = gp.hadm_id
)
SELECT
  total_patients,
  any_glp1_use,
  ROUND(100.0 * any_glp1_use / total_patients, 2) AS prevalence_pct,
  initiated_first_72h,
  ROUND(100.0 * initiated_first_72h / total_patients, 2) AS initiation_first_72h_pct,
  initiated_final_24h,
  ROUND(100.0 * initiated_final_24h / total_patients, 2) AS initiation_final_24h_pct,
  ROUND(
    (100.0 * initiated_final_24h / total_patients) - (100.0 * initiated_first_72h / total_patients),
    2
  ) AS absolute_change_pct,
  CASE 
    WHEN initiated_first_72h > 0 THEN
      ROUND(
        (initiated_final_24h - initiated_first_72h) * 100.0 / initiated_first_72h,
        3
      )
    ELSE NULL 
  END AS relative_change
FROM cohort_stats;