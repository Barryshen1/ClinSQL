WITH cohort AS (
  -- Index admissions: female, age 55-65, Medicare, admitted from ED, principal diagnosis = cellulitis
  SELECT
    a.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    -- LOS in days (fractional)
    SAFE_DIVIDE(TIMESTAMP_DIFF(a.dischtime, a.admittime, MINUTE), 1440.0) AS los_days
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON p.subject_id = a.subject_id
  JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
    ON d.subject_id = a.subject_id
    AND d.hadm_id = a.hadm_id
    AND d.seq_num = 1 -- principal diagnosis
  JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` dicd
    ON dicd.icd_code = d.icd_code
    AND dicd.icd_version = d.icd_version
  WHERE
    LOWER(p.gender) = 'f'
    AND p.anchor_age BETWEEN 55 AND 65
    AND LOWER(COALESCE(a.insurance, '')) LIKE '%medicare%'
    AND LOWER(COALESCE(a.admission_location, '')) LIKE '%emergency%'
    AND LOWER(COALESCE(dicd.long_title, '')) LIKE '%cellulitis%'
),

cohort_with_readmit_flag AS (
  -- For each index admission, determine whether there is any readmission within 30 days
  SELECT
    c.*,
    -- boolean flag: has at least one readmission within 30 days after index discharge
    EXISTS (
      SELECT 1
      FROM `physionet-data.mimiciv_3_1_hosp.admissions` a2
      WHERE a2.subject_id = c.subject_id
        AND a2.hadm_id != c.hadm_id
        AND a2.admittime > c.dischtime
        AND a2.admittime <= TIMESTAMP_ADD(c.dischtime, INTERVAL 30 DAY)
    ) AS readmit_30d
  FROM cohort c
)

SELECT
  -- overall counts
  COUNT(*) AS n_index_admissions,
  SUM(CASE WHEN readmit_30d THEN 1 ELSE 0 END) AS n_readmit_within_30d,
  ROUND(SAFE_DIVIDE(SUM(CASE WHEN readmit_30d THEN 1 ELSE 0 END), COUNT(*)) * 100, 2) AS readmit_30d_rate_percent,
  -- median LOS for readmitted vs non-readmitted (approximate median)
  APPROX_QUANTILES(IF(readmit_30d, los_days, NULL), 100)[OFFSET(50)] AS median_los_days_readmitted,
  APPROX_QUANTILES(IF(NOT readmit_30d, los_days, NULL), 100)[OFFSET(50)] AS median_los_days_not_readmitted,
  -- percent of index stays > 7 days
  ROUND(SAFE_DIVIDE(SUM(CASE WHEN los_days > 7 THEN 1 ELSE 0 END), COUNT(*)) * 100, 2) AS pct_index_stays_gt_7_days
FROM cohort_with_readmit_flag;