WITH patient_cohort AS (
  SELECT 
    p.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    DATETIME_DIFF(a.dischtime, a.admittime, DAY) AS los_days,
    di.seq_num,
    CASE WHEN di.seq_num = 1 THEN 'primary' ELSE 'secondary' END AS diagnosis_role
  FROM `physionet-data.mimiciv_3_1_hosp`.patients p
  INNER JOIN `physionet-data.mimiciv_3_1_hosp`.admissions a
    ON p.subject_id = a.subject_id
  INNER JOIN `physionet-data.mimiciv_3_1_hosp`.diagnoses_icd di
    ON a.hadm_id = di.hadm_id
  INNER JOIN `physionet-data.mimiciv_3_1_hosp`.d_icd_diagnoses d_diag
    ON di.icd_code = d_diag.icd_code AND di.icd_version = d_diag.icd_version
  WHERE p.gender = 'M'
    AND p.anchor_age BETWEEN 51 AND 61
    AND d_diag.icd_code LIKE 'K85%'
    AND di.icd_version = 10
    AND a.dischtime IS NOT NULL
    AND a.admittime IS NOT NULL
    AND a.dischtime >= a.admittime
),
imaging_procedures AS (
  SELECT 
    pi.hadm_id,
    COUNT(*) AS imaging_count
  FROM `physionet-data.mimiciv_3_1_hosp`.procedures_icd pi
  INNER JOIN `physionet-data.mimiciv_3_1_hosp`.d_icd_procedures d_proc
    ON pi.icd_code = d_proc.icd_code AND pi.icd_version = d_proc.icd_version
  WHERE LOWER(d_proc.long_title) LIKE '%ct%'
     OR LOWER(d_proc.long_title) LIKE '%computed%'
     OR LOWER(d_proc.long_title) LIKE '%radiography%'
     OR LOWER(d_proc.long_title) LIKE '%x-ray%'
  GROUP BY pi.hadm_id
),
cohort_with_imaging AS (
  SELECT 
    pc.subject_id,
    pc.hadm_id,
    pc.los_days,
    pc.diagnosis_role,
    COALESCE(ip.imaging_count, 0) AS imaging_count
  FROM patient_cohort pc
  LEFT JOIN imaging_procedures ip ON pc.hadm_id = ip.hadm_id
),
stratified_cohort AS (
  SELECT 
    diagnosis_role,
    CASE 
      WHEN los_days BETWEEN 1 AND 3 THEN '1-3 days'
      WHEN los_days BETWEEN 4 AND 7 THEN '4-7 days'
      ELSE NULL 
    END AS los_group,
    imaging_count
  FROM cohort_with_imaging
  WHERE los_days BETWEEN 1 AND 7
)
SELECT 
  diagnosis_role,
  los_group,
  COUNT(*) AS patient_count,
  AVG(imaging_count) AS mean_radiography_ct_per_admission
FROM stratified_cohort
WHERE los_group IS NOT NULL
GROUP BY diagnosis_role, los_group
ORDER BY diagnosis_role, los_group;