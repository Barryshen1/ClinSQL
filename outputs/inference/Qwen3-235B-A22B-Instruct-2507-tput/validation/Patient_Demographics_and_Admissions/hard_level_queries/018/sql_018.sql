WITH patient_admissions AS (
  SELECT
    a.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    DATETIME_DIFF(a.dischtime, a.admittime, DAY) AS los_days,
    -- Compute age at admission
    (EXTRACT(YEAR FROM a.admittime) - p.anchor_year + p.anchor_age) AS age_at_admit
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON a.subject_id = p.subject_id
  JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` diag
    ON a.hadm_id = diag.hadm_id
  JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` d_diag
    ON diag.icd_code = d_diag.icd_code AND diag.icd_version = d_diag.icd_version
  WHERE
    -- Female
    p.gender = 'F'
    -- Age 58-68 at admission
    AND (EXTRACT(YEAR FROM a.admittime) - p.anchor_year + p.anchor_age) BETWEEN 58 AND 68
    -- Admitted via ED
    AND a.admission_location = 'EMERGENCY ROOM'
    -- Medicare
    AND a.insurance = 'Medicare'
    -- Principal diagnosis: femoral neck fracture
    AND diag.seq_num = 1
    AND LOWER(d_diag.long_title) LIKE '%femoral neck fracture%'
),

-- Add readmission flag
index_with_readmission AS (
  SELECT
    pa.*,
    LEAD(pa.admittime) OVER (PARTITION BY pa.subject_id ORDER BY pa.admittime) AS next_admittime,
    -- Flag if readmitted within 30 days
    CASE
      WHEN LEAD(pa.admittime) OVER (PARTITION BY pa.subject_id ORDER BY pa.admittime) IS NOT NULL
        AND DATETIME_DIFF(LEAD(pa.admittime) OVER (PARTITION BY pa.subject_id ORDER BY pa.admittime), pa.dischtime, DAY) <= 30
      THEN 1
      ELSE 0
    END AS readmitted_30d
  FROM patient_admissions pa
),

-- Aggregate statistics
summary_stats AS (
  SELECT
    readmitted_30d,
    los_days,
    -- Flag if LOS > 8 days
    CASE WHEN los_days > 8 THEN 1 ELSE 0 END AS los_gt_8
  FROM index_with_readmission
)

-- Final output: metrics
SELECT
  -- 30-day readmission rate
  ROUND(AVG(CAST(readmitted_30d AS FLOAT64)) * 100, 2) AS readmission_rate_30d_percent,
  -- Median LOS for readmitted
  APPROX_QUANTILES(CASE WHEN readmitted_30d = 1 THEN los_days END, 100)[OFFSET(50)] AS median_los_readmitted_days,
  -- Median LOS for non-readmitted
  APPROX_QUANTILES(CASE WHEN readmitted_30d = 0 THEN los_days END, 100)[OFFSET(50)] AS median_los_non_readmitted_days,
  -- Percent of index stays > 8 days
  ROUND(AVG(CAST(los_gt_8 AS FLOAT64)) * 100, 2) AS percent_los_gt_8_days
FROM summary_stats;