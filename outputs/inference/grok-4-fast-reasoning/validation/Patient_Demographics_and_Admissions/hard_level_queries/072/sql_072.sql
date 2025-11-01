WITH index_cohort AS (
  SELECT 
    a.subject_id, 
    a.hadm_id, 
    a.admittime, 
    a.dischtime,
    TIMESTAMP_DIFF(a.dischtime, a.admittime, DAY) AS los_days
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` p 
    ON a.subject_id = p.subject_id
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` diag 
    ON a.hadm_id = diag.hadm_id
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` icd 
    ON diag.icd_code = icd.icd_code 
    AND diag.icd_version = icd.icd_version
  WHERE p.gender = 'F'
    AND p.anchor_age BETWEEN 77 AND 87
    AND a.insurance = 'Medicare'
    AND a.admission_location = 'SNF'
    AND a.hospital_expire_flag = 0
    AND diag.seq_num = 1
    AND LOWER(icd.long_title) LIKE '%acute respiratory failure%'
),
readmission_flags AS (
  SELECT 
    i.subject_id,
    i.hadm_id,
    i.admittime,
    i.dischtime,
    i.los_days,
    CASE WHEN COUNT(r.hadm_id) > 0 THEN 1 ELSE 0 END AS readmitted
  FROM index_cohort i
  LEFT JOIN `physionet-data.mimiciv_3_1_hosp.admissions` r
    ON i.subject_id = r.subject_id
    AND r.hadm_id != i.hadm_id
    AND r.admittime > i.dischtime
    AND r.admittime <= TIMESTAMP_ADD(i.dischtime, INTERVAL 30 DAY)
  GROUP BY 
    i.subject_id, i.hadm_id, i.admittime, i.dischtime, i.los_days
)
SELECT 
  ROUND(SUM(readmitted) * 100.0 / COUNT(*), 2) AS readmission_rate_percent,
  (SELECT PERCENTILE_CONT(los_days, 0.5) FROM readmission_flags WHERE readmitted = 1) AS median_los_readmitted_days,
  (SELECT PERCENTILE_CONT(los_days, 0.5) FROM readmission_flags WHERE readmitted = 0) AS median_los_not_readmitted_days,
  ROUND(SUM(CASE WHEN los_days > 8 THEN 1 ELSE 0 END) * 100.0 / COUNT(*), 2) AS percent_index_stays_gt8days
FROM readmission_flags;