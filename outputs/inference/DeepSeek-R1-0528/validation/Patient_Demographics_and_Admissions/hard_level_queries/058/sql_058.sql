WITH cohort AS (
  SELECT 
    adm.subject_id,
    adm.hadm_id,
    adm.admittime,
    adm.dischtime,
    (p.anchor_age + (EXTRACT(YEAR FROM adm.admittime) - p.anchor_year)) AS age_at_admission,
    adm.hospital_expire_flag
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` adm
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON adm.subject_id = p.subject_id
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` diag
    ON adm.hadm_id = diag.hadm_id
  WHERE 
    p.gender = 'M'
    AND adm.admission_location = 'EMERGENCY ROOM'
    AND adm.insurance = 'Medicare'
    AND diag.seq_num = 1
    AND (
      (diag.icd_version = 9 AND diag.icd_code IN ('569.3','578.1','455.2','455.5','455.8','562.02','562.03','562.12','562.13','569.85','569.86'))
      OR
      (diag.icd_version = 10 AND diag.icd_code IN ('K62.2','K62.3','K62.5','K62.8','K62.81','K62.89','K62.9','K92.2'))
    )
),
filtered_cohort AS (
  SELECT 
    subject_id,
    hadm_id,
    admittime,
    dischtime
  FROM cohort
  WHERE 
    age_at_admission BETWEEN 50 AND 60
    AND hospital_expire_flag = 0
),
cohort_with_readmission AS (
  SELECT 
    fc.*,
    TIMESTAMP_DIFF(fc.dischtime, fc.admittime, SECOND) / 86400.0 AS los_days,
    CASE WHEN radm.hadm_id IS NOT NULL THEN 1 ELSE 0 END AS readmission_flag
  FROM filtered_cohort fc
  LEFT JOIN `physionet-data.mimiciv_3_1_hosp.admissions` radm
    ON fc.subject_id = radm.subject_id
    AND radm.hadm_id <> fc.hadm_id
    AND radm.admittime > fc.dischtime
    AND radm.admittime <= TIMESTAMP_ADD(fc.dischtime, INTERVAL 30 DAY)
),
metrics_by_group AS (
  SELECT 
    readmission_flag,
    COUNT(*) AS num_admissions,
    PERCENTILE_CONT(los_days, 0.5) OVER (PARTITION BY readmission_flag) AS median_los_days,
    AVG(CASE WHEN los_days > 6 THEN 1.0 ELSE 0.0 END) OVER (PARTITION BY readmission_flag) * 100 AS percent_los_above_6
  FROM cohort_with_readmission
  GROUP BY readmission_flag, los_days
)
SELECT 
  'Overall' AS measure,
  COUNT(*) AS total_index_admissions,
  AVG(readmission_flag) * 100 AS readmission_rate,
  NULL AS median_los_days,
  NULL AS percent_los_above_6
FROM cohort_with_readmission
UNION ALL
SELECT 
  'Readmitted' AS measure,
  NULL,
  NULL,
  median_los_days,
  percent_los_above_6
FROM metrics_by_group
WHERE readmission_flag = 1
GROUP BY readmission_flag, median_los_days, percent_los_above_6
UNION ALL
SELECT 
  'Not Readmitted' AS measure,
  NULL,
  NULL,
  median_los_days,
  percent_los_above_6
FROM metrics_by_group
WHERE readmission_flag = 0
GROUP BY readmission_flag, median_los_days, percent_los_above_6;