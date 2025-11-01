WITH index_admissions AS (
  SELECT 
    adm.subject_id,
    adm.hadm_id,
    adm.admittime,
    adm.dischtime,
    adm.insurance,
    adm.admission_type,
    adm.admission_location,
    DATETIME_DIFF(adm.dischtime, adm.admittime, DAY) AS los_days,
    -- Exclude patients who died during index admission
    CASE WHEN adm.deathtime IS NOT NULL THEN 1 ELSE 0 END AS died_in_index,
    -- Check for readmission within 30 days (excluding same admission and deaths)
    CASE WHEN EXISTS (
      SELECT 1 
      FROM `physionet-data.mimiciv_3_1_hosp.admissions` readm 
      WHERE readm.subject_id = adm.subject_id 
        AND readm.hadm_id != adm.hadm_id 
        AND readm.admittime > adm.dischtime 
        AND DATETIME_DIFF(readm.admittime, adm.dischtime, DAY) <= 30
    ) THEN 1 ELSE 0 END AS readmitted_30d
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` adm
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` pat
    ON adm.subject_id = pat.subject_id
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` diag
    ON adm.hadm_id = diag.hadm_id
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` d
    ON diag.icd_code = d.icd_code AND diag.icd_version = d.icd_version
  WHERE pat.gender = 'F'
    AND pat.anchor_age BETWEEN 76 AND 86
    AND adm.insurance = 'Medicare'
    AND adm.admission_type = 'TRANSFER'
    AND diag.seq_num = 1
    AND (d.icd_code LIKE '410%' OR d.icd_code LIKE 'I21%')
    -- Exclude in-hospital deaths to avoid bias in readmission calculation
    AND adm.deathtime IS NULL
),
cohort_stats AS (
  SELECT
    COUNT(*) AS total_index_admissions,
    AVG(100.0 * readmitted_30d) AS readmission_rate_30d,
    -- Use APPROX_QUANTILES and extract median (0.5 quantile at index 1)
    (APPROX_QUANTILES(CASE WHEN readmitted_30d = 1 THEN los_days END, 2))[OFFSET(1)] AS median_los_readmitted,
    (APPROX_QUANTILES(CASE WHEN readmitted_30d = 0 THEN los_days END, 2))[OFFSET(1)] AS median_los_not_readmitted,
    AVG(100.0 * CASE WHEN los_days > 4 THEN 1 ELSE 0 END) AS percent_los_gt_4_days
  FROM index_admissions
)
SELECT
  total_index_admissions,
  readmission_rate_30d,
  median_los_readmitted,
  median_los_not_readmitted,
  percent_los_gt_4_days
FROM cohort_stats;