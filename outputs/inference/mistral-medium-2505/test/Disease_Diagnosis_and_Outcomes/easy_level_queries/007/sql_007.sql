WITH ugi_patients AS (
  -- Get female patients aged 84-94 with primary UGIB diagnosis
  SELECT
    a.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    TIMESTAMP_DIFF(a.dischtime, a.admittime, HOUR) / 24 AS los_days
  FROM
    `physionet-data.mimiciv_3_1_hosp.patients` p
  JOIN
    `physionet-data.mimiciv_3_1_hosp.admissions` a
    ON p.subject_id = a.subject_id
  JOIN
    `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
    ON a.subject_id = d.subject_id AND a.hadm_id = d.hadm_id
  JOIN
    `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` diag
    ON d.icd_code = diag.icd_code AND d.icd_version = diag.icd_version
  WHERE
    p.gender = 'F'
    AND p.anchor_age BETWEEN 84 AND 94
    AND d.seq_num = 1  -- Primary diagnosis
    AND (
      -- ICD-9 codes for UGIB (578.x)
      (d.icd_version = 9 AND d.icd_code LIKE '578.%')
      OR
      -- ICD-10 codes for UGIB (K92.2)
      (d.icd_version = 10 AND d.icd_code = 'K922')
    )
    AND a.dischtime IS NOT NULL  -- Ensure discharge time exists
),

los_stats AS (
  -- Calculate percentiles for LOS
  SELECT
    PERCENTILE_CONT(los_days, 0.25) OVER() AS q1,
    PERCENTILE_CONT(los_days, 0.75) OVER() AS q3
  FROM
    ugi_patients
  LIMIT 1
)

-- Return the IQR (Q3 - Q1)
SELECT
  q3 - q1 AS iqr_los_days
FROM
  los_stats;