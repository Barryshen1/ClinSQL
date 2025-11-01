WITH base_cohort AS (
  SELECT
    a.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    -- Calculate age at admission using MIMIC-IV standard method
    p.anchor_age + (EXTRACT(YEAR FROM a.admittime) - p.anchor_year) AS age_at_admission
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON a.subject_id = p.subject_id
  -- Join with diagnoses_icd to get principal diagnosis (seq_num = 1)
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
    ON a.hadm_id = d.hadm_id AND a.subject_id = d.subject_id
  WHERE
    -- Male patients
    p.gender = 'M'
    -- Age between 83 and 93
    AND p.anchor_age + (EXTRACT(YEAR FROM a.admittime) - p.anchor_year) BETWEEN 83 AND 93
    -- Medicare insurance
    AND a.insurance = 'Medicare'
    -- Admitted via ED
    AND (a.admission_location LIKE '%EMERGENCY%' OR a.admission_location LIKE '%ED%')
    -- Principal diagnosis (seq_num = 1)
    AND d.seq_num = 1
    -- TIA diagnosis codes
    AND (
      -- ICD-9 codes for TIA (with decimal)
      (d.icd_version = 9 AND d.icd_code IN ('435.0', '435.1', '435.2', '435.3', '435.8', '435.9'))
      OR
      -- ICD-10 codes for TIA (without decimal)
      (d.icd_version = 10 AND d.icd_code IN ('G450', 'G451', 'G452', 'G453', 'G454', 'G458', 'G459'))
    )
),
cohort_with_readmission AS (
  SELECT
    *,
    -- Calculate LOS in fractional days
    TIMESTAMP_DIFF(dischtime, admittime, SECOND) / 86400.0 AS los_days,
    -- Get next admission time for readmission calculation
    LEAD(admittime) OVER (PARTITION BY subject_id ORDER BY admittime) AS next_admittime
  FROM base_cohort
),
cohort_final AS (
  SELECT
    *,
    -- Flag for readmission within 30 days (with NULL safety)
    CASE 
      WHEN next_admittime IS NOT NULL AND next_admittime <= dischtime + INTERVAL '30' DAY THEN 1 
      ELSE 0 
    END AS readmitted_30d
  FROM cohort_with_readmission
)
SELECT
  -- 30-day readmission rate (with division safety)
  SAFE_DIVIDE(SUM(readmitted_30d), COUNT(*)) AS readmission_rate_30d,
  -- Median LOS for readmitted patients (with NULL handling)
  APPROX_QUANTILES(IF(readmitted_30d = 1, los_days, NULL), 100)[SAFE_OFFSET(50)] AS median_los_readmitted,
  -- Median LOS for non-readmitted patients (with NULL handling)
  APPROX_QUANTILES(IF(readmitted_30d = 0, los_days, NULL), 100)[SAFE_OFFSET(50)] AS median_los_non_readmitted,
  -- Percent of index stays > 10 days
  SAFE_DIVIDE(COUNTIF(los_days > 10), COUNT(*)) * 100 AS percent_stays_gt_10d
FROM cohort_final;