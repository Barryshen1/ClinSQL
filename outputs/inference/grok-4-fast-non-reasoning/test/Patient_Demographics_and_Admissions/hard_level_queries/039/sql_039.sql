WITH cohort_raw AS (
  -- Compute row number first
  SELECT 
    p.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    EXTRACT(DAY FROM a.dischtime - a.admittime) AS los_index,
    ROW_NUMBER() OVER (PARTITION BY p.subject_id ORDER BY a.admittime) AS rn
  FROM `physionet-data.mimiciv_3_1_hosp.patients` p
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a
    ON p.subject_id = a.subject_id
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
    ON a.hadm_id = d.hadm_id
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` icd
    ON d.icd_code = icd.icd_code AND d.icd_version = icd.icd_version
  WHERE p.gender = 'M'
    AND p.anchor_age BETWEEN 65 AND 75
    AND a.insurance = 'Medicare'
    AND a.admission_location = 'EMERGENCY ROOM'
    AND a.hospital_expire_flag = 0
    AND a.dischtime IS NOT NULL
    AND a.admittime < a.dischtime
    AND d.seq_num = 1
    AND d.icd_version = '10'
    AND d.icd_code LIKE 'J96%'
),
cohort AS (
  SELECT 
    subject_id,
    hadm_id AS index_hadm_id,
    admittime AS index_admittime,
    dischtime AS index_dischtime,
    los_index
  FROM cohort_raw
  WHERE rn = 1
),
readmits AS (
  -- Flag if patient had readmission within 30 days of index discharge
  SELECT 
    c.*,
    CASE 
      WHEN EXISTS (
        SELECT 1
        FROM `physionet-data.mimiciv_3_1_hosp.admissions` a2
        INNER JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d2
          ON a2.hadm_id = d2.hadm_id AND d2.seq_num = 1
        WHERE a2.subject_id = c.subject_id
          AND a2.hadm_id != c.index_hadm_id
          AND a2.admittime > c.index_dischtime
          AND a2.admittime <= DATE_ADD(c.index_dischtime, INTERVAL 30 DAY)
          AND a2.hospital_expire_flag = 0
          AND a2.dischtime IS NOT NULL
          AND d2.icd_version = '10'
          AND d2.icd_code NOT LIKE 'Z%'  -- Exclude observation/rehab as readmits
      ) THEN 1 ELSE 0 
    END AS readmitted
  FROM cohort c
),
summary AS (
  SELECT
    -- 30-day readmission rate (%)
    SAFE_DIVIDE(SUM(readmitted), COUNT(*)) * 100 AS readmission_rate_pct,
    
    -- Median LOS by readmission status
    PERCENTILE_CONT(los_index, 0.5) OVER (PARTITION BY readmitted) AS median_los,
    
    -- % LOS >9 days (full cohort)
    SAFE_DIVIDE(COUNTIF(los_index > 9), COUNT(*)) * 100 AS pct_los_gt_9_days
  FROM readmits
),
final_summary AS (
  SELECT
    readmission_rate_pct,
    MAX(CASE WHEN median_los = (SELECT median_los FROM summary WHERE readmitted = 1) THEN median_los END) AS median_los_readmitted,
    MAX(CASE WHEN median_los = (SELECT median_los FROM summary WHERE readmitted = 0) THEN median_los END) AS median_los_non_readmitted,
    pct_los_gt_9_days
  FROM summary
  GROUP BY readmission_rate_pct, pct_los_gt_9_days
)
SELECT
  readmission_rate_pct,
  median_los_readmitted,
  median_los_non_readmitted,
  pct_los_gt_9_days
FROM final_summary;