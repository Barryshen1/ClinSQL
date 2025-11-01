WITH diag_flags AS (
  -- For each hospital admission, flag whether pneumonia and COPD diagnoses are present
  SELECT
    di.subject_id,
    di.hadm_id,
    MAX(CASE WHEN LOWER(d.long_title) LIKE '%pneumonia%' THEN 1 ELSE 0 END) AS has_pneumonia,
    MAX(CASE
          WHEN LOWER(d.long_title) LIKE '%chronic obstructive%' OR
               LOWER(d.long_title) LIKE '%copd%' OR
               LOWER(d.long_title) LIKE '%emphysema%'
          THEN 1 ELSE 0 END) AS has_copd
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` di
  LEFT JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` d
    ON di.icd_code = d.icd_code
    AND di.icd_version = d.icd_version
  GROUP BY di.subject_id, di.hadm_id
),

cohort AS (
  -- Select male patients aged 68-78 with both pneumonia and COPD on the same admission
  SELECT
    a.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    p.gender,
    p.anchor_age,
    TIMESTAMP_DIFF(a.dischtime, a.admittime, SECOND) / 86400.0 AS los_days
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON a.subject_id = p.subject_id
  JOIN diag_flags df
    ON a.subject_id = df.subject_id
    AND a.hadm_id = df.hadm_id
  WHERE p.gender = 'M'
    AND p.anchor_age BETWEEN 68 AND 78
    AND df.has_pneumonia = 1
    AND df.has_copd = 1
    -- Ensure valid times
    AND a.admittime IS NOT NULL
    AND a.dischtime IS NOT NULL
    AND a.dischtime > a.admittime
)

SELECT
  COUNT(*) AS n_admissions,
  -- Approximate 75th percentile of hospital LOS in days
  APPROX_QUANTILES(los_days, 100)[OFFSET(75)] AS los_75th_percentile_days
FROM cohort;