WITH eligible_admissions AS (
  SELECT
    a.hadm_id,
    a.subject_id,
    a.admittime,
    a.dischtime,
    a.hospital_expire_flag,
    DATETIME_DIFF(a.dischtime, a.admittime, DAY) AS los_days,
    -- Compute age at admission
    p.anchor_age + (EXTRACT(YEAR FROM a.admittime) - p.anchor_year) AS age_at_admit
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON a.subject_id = p.subject_id
  -- Join to get principal diagnosis
  JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` diag
    ON a.hadm_id = diag.hadm_id
  JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` d_diag
    ON diag.icd_code = d_diag.icd_code AND diag.icd_version = d_diag.icd_version
  WHERE
    -- Male
    p.gender = 'M'
    -- Age 65–75 at admission
    AND (p.anchor_age + (EXTRACT(YEAR FROM a.admittime) - p.anchor_year)) BETWEEN 65 AND 75
    -- Insurance: Medicare
    AND LOWER(a.insurance) = 'medicare'
    -- Admitted from ED
    AND LOWER(a.admission_location) LIKE 'emergency room%'
    -- Principal diagnosis (seq_num = 1)
    AND diag.seq_num = 1
    -- Diagnosis: acute respiratory failure (case-insensitive)
    AND LOWER(d_diag.long_title) LIKE '%acute respiratory failure%'
    -- Valid admission and discharge times
    AND a.admittime IS NOT NULL
    AND a.dischtime IS NOT NULL
    -- Exclude in-hospital deaths (cannot be readmitted)
    AND a.hospital_expire_flag = 0
),
readmission_flag AS (
  SELECT
    e.*,
    -- Check if there is a next admission within 30 days
    LEAD(e.admittime) OVER (PARTITION BY e.subject_id ORDER BY e.admittime) AS next_admittime,
    CASE
      WHEN LEAD(e.admittime) OVER (PARTITION BY e.subject_id ORDER BY e.admittime) <= DATETIME_ADD(e.dischtime, INTERVAL 30 DAY)
        THEN 1
      ELSE 0
    END AS readmitted_30d
  FROM eligible_admissions e
),
summary_stats AS (
  SELECT
    readmitted_30d,
    los_days,
    -- Flag if LOS > 9 days
    CASE WHEN los_days > 9 THEN 1 ELSE 0 END AS los_gt_9
  FROM readmission_flag
)
SELECT
  -- 30-day readmission rate
  AVG(CAST(readmitted_30d AS FLOAT64)) AS readmission_rate_30d,
  -- Median index LOS for readmitted (readmitted_30d = 1)
  APPROX_QUANTILES(IF(readmitted_30d = 1, los_days, NULL), 100)[OFFSET(50)] AS median_los_readmitted,
  -- Median index LOS for non-readmitted (readmitted_30d = 0)
  APPROX_QUANTILES(IF(readmitted_30d = 0, los_days, NULL), 100)[OFFSET(50)] AS median_los_non_readmitted,
  -- Percent of index admissions with LOS > 9 days
  AVG(CAST(los_gt_9 AS FLOAT64)) * 100 AS percent_los_gt_9_days
FROM summary_stats;