WITH ap_patients AS (
  SELECT DISTINCT di.subject_id, di.hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` di
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` dd
    ON di.icd_code = dd.icd_code
   AND di.icd_version = dd.icd_version
  WHERE 
    -- ICD-9 acute pancreatitis
    (di.icd_version = 9 AND di.icd_code = '5770')
    -- ICD-10 acute pancreatitis
    OR (di.icd_version = 10 AND di.icd_code LIKE 'K85%')
),
ap_male_age AS (
  SELECT ap.subject_id, ap.hadm_id,
         p.anchor_age, p.gender,
         adm.admittime, adm.dischtime,
         TIMESTAMP_DIFF(adm.dischtime, adm.admittime, HOUR)/24.0 AS los_days
  FROM ap_patients ap
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON ap.subject_id = p.subject_id
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` adm
    ON ap.subject_id = adm.subject_id
   AND ap.hadm_id = adm.hadm_id
  WHERE p.gender = 'M'
    AND p.anchor_age BETWEEN 42 AND 52
    AND adm.admittime IS NOT NULL
    AND adm.dischtime IS NOT NULL
),
diag_proc_counts AS (
  SELECT a.subject_id, a.hadm_id, a.los_days,
         CASE 
           WHEN a.los_days >= 1 AND a.los_days <= 4 THEN 'LOS_1_4'
           WHEN a.los_days >= 5 AND a.los_days <= 7 THEN 'LOS_5_7'
         END AS los_group,
         COUNT(*) AS diagnostic_proc_count
  FROM ap_male_age a
  LEFT JOIN `physionet-data.mimiciv_3_1_hosp.procedures_icd` pi
    ON a.subject_id = pi.subject_id
   AND a.hadm_id = pi.hadm_id
  LEFT JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_procedures` dpi
    ON pi.icd_code = dpi.icd_code
   AND pi.icd_version = dpi.icd_version
  WHERE a.los_days BETWEEN 1 AND 7
    AND (LOWER(dpi.long_title) LIKE '%diagnostic%')
  GROUP BY a.subject_id, a.hadm_id, a.los_days, los_group
)
SELECT los_group,
       COUNT(*) AS patient_count,
       ROUND(AVG(diagnostic_proc_count),2) AS mean_diag_proc,
       MIN(diagnostic_proc_count) AS min_diag_proc,
       MAX(diagnostic_proc_count) AS max_diag_proc
FROM diag_proc_counts
GROUP BY los_group
ORDER BY los_group;