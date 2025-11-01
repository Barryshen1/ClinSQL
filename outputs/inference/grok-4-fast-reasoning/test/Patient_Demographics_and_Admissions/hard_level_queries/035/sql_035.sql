WITH index_adms AS (
  SELECT 
    a.subject_id, 
    a.hadm_id, 
    a.admittime, 
    a.dischtime,
    DATE_DIFF(a.dischtime, a.admittime, DAY) AS los
  FROM 
    `physionet-data.mimiciv_3_1_hosp.admissions` a
  INNER JOIN 
    `physionet-data.mimiciv_3_1_hosp.patients` p 
    ON a.subject_id = p.subject_id
  INNER JOIN 
    `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` diag 
    ON a.hadm_id = diag.hadm_id AND diag.seq_num = 1
  INNER JOIN 
    `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` icd 
    ON diag.icd_code = icd.icd_code AND diag.icd_version = icd.icd_version
  WHERE 
    p.gender = 'M'
    AND p.anchor_age BETWEEN 68 AND 78
    AND a.insurance = 'MC'
    AND a.admission_location = 'SNFC'
    AND LOWER(icd.long_title) LIKE '%urinary tract infection%'
    AND a.hospital_expire_flag = 0
    AND a.dischtime IS NOT NULL
),
cohort AS (
  SELECT 
    *,
    EXISTS (
      SELECT 1 
      FROM `physionet-data.mimiciv_3_1_hosp.admissions` a2
      WHERE 
        a2.subject_id = index_adms.subject_id
        AND a2.hadm_id != index_adms.hadm_id
        AND a2.admittime > index_adms.dischtime
        AND a2.admittime <= TIMESTAMP_ADD(index_adms.dischtime, INTERVAL 30 DAY)
        AND a2.dischtime IS NOT NULL
    ) AS has_readmission
  FROM index_adms
)
SELECT 
  COUNT(*) AS total_index_admissions,
  SUM(CASE WHEN has_readmission THEN 1 ELSE 0 END) AS num_readmitted,
  SAFE_DIVIDE(SUM(CASE WHEN has_readmission THEN 1 ELSE 0 END), COUNT(*)) * 100 AS readmission_rate_pct,
  (SELECT APPROX_QUANTILES(los, 2)[OFFSET(1)] FROM cohort c2 WHERE c2.has_readmission) AS median_los_readmitted_days,
  (SELECT APPROX_QUANTILES(los, 2)[OFFSET(1)] FROM cohort c2 WHERE NOT c2.has_readmission) AS median_los_non_readmitted_days,
  SAFE_DIVIDE(SUM(CASE WHEN los > 6 THEN 1 ELSE 0 END), COUNT(*)) * 100 AS pct_stays_gt6_days
FROM cohort;