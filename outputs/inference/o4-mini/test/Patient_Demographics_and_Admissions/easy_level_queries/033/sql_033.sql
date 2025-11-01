WITH dialysis_admissions AS (
  -- Find all distinct hospital admissions with at least one dialysis procedure
  SELECT DISTINCT
    p_icd.subject_id,
    p_icd.hadm_id
  FROM
    `physionet-data.mimiciv_3_1_hosp.procedures_icd` p_icd
    JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_procedures` d_proc
      ON p_icd.icd_code = d_proc.icd_code
      AND p_icd.icd_version = d_proc.icd_version
  WHERE
    LOWER(d_proc.long_title) LIKE '%dialysis%'
),
filtered_admissions AS (
  -- Filter to male patients aged 44-54 and join to admissions
  SELECT
    a.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime
  FROM
    dialysis_admissions da
    JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a
      ON da.hadm_id = a.hadm_id
    JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
      ON a.subject_id = p.subject_id
  WHERE
    p.gender = 'M'
    AND p.anchor_age BETWEEN 44 AND 54
    AND a.admittime IS NOT NULL
    AND a.dischtime IS NOT NULL
),
los_calculation AS (
  -- Compute length of stay in days for each admission
  SELECT
    hadm_id,
    TIMESTAMP_DIFF(dischtime, admittime, DAY) AS los_days
  FROM
    filtered_admissions
)
-- Compute the standard deviation of LOS across all qualifying admissions
SELECT
  STDDEV_SAMP(los_days) AS sd_los_days
FROM
  los_calculation;