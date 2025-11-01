WITH index_admissions AS (
  SELECT
    a.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` AS a
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` AS p
    ON p.subject_id = a.subject_id
  JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` AS di
    ON di.subject_id = a.subject_id
   AND di.hadm_id = a.hadm_id
   AND di.seq_num = 1  -- principal diagnosis
  JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` AS dd
    ON dd.icd_code = di.icd_code
   AND dd.icd_version = di.icd_version
  WHERE a.edregtime IS NOT NULL                    -- admitted from ED
    AND LOWER(a.insurance) LIKE '%medicare%'        -- Medicare patients
    AND p.gender = 'F'                               -- female
    AND p.anchor_age BETWEEN 55 AND 65             -- age 55-65
    AND LOWER(dd.long_title) LIKE '%cellulitis%'     -- principal cellulitis
),
cohort_with_readmit AS (
  SELECT
    idx.subject_id,
    idx.hadm_id,
    idx.admittime,
    idx.dischtime,
    DATE_DIFF(DATE(idx.dischtime), DATE(idx.admittime), DAY) AS los_days,
    CASE
      WHEN EXISTS (
        SELECT 1
        FROM `physionet-data.mimiciv_3_1_hosp.admissions` a2
        WHERE a2.subject_id = idx.subject_id
          AND a2.hadm_id <> idx.hadm_id
          AND a2.admittime >= idx.dischtime
          AND a2.admittime <= TIMESTAMP_ADD(idx.dischtime, INTERVAL 30 DAY)
      )
      THEN 1 ELSE 0
    END AS readmit_flag
  FROM index_admissions AS idx
)
SELECT
  ROUND(100.0 * SUM(readmit_flag) / COUNT(*), 2) AS readmission_30d_pct,
  (SELECT APPROX_QUANTILES(los_days, 2)[OFFSET(1)]
     FROM cohort_with_readmit
     WHERE readmit_flag = 1) AS median_los_readmit_days,
  (SELECT APPROX_QUANTILES(los_days, 2)[OFFSET(1)]
     FROM cohort_with_readmit
     WHERE readmit_flag = 0) AS median_los_non_readmit_days,
  100.0 * SUM(CASE WHEN los_days > 7 THEN 1 ELSE 0 END) / COUNT(*) AS pct_index_los_gt_7_days
FROM cohort_with_readmit;