WITH diag_flags AS (
  -- For each admission, flag presence of heart failure and COPD diagnoses
  SELECT
    di.subject_id,
    di.hadm_id,
    MAX(CASE WHEN REGEXP_CONTAINS(LOWER(dic.long_title), r'heart failure') THEN 1 ELSE 0 END) AS has_hf,
    MAX(CASE WHEN REGEXP_CONTAINS(LOWER(dic.long_title), r'chronic obstructive|copd|obstructive pulmonary') THEN 1 ELSE 0 END) AS has_copd
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` di
  LEFT JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` dic
    ON di.icd_code = dic.icd_code
   AND di.icd_version = dic.icd_version
  GROUP BY di.subject_id, di.hadm_id
),

cohort AS (
  -- Select female patients aged 77-87 with both HF and COPD on the same admission
  SELECT
    a.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    p.gender,
    p.anchor_age,
    SAFE_DIVIDE(TIMESTAMP_DIFF(a.dischtime, a.admittime, SECOND), 86400.0) AS los_days
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON a.subject_id = p.subject_id
  JOIN diag_flags df
    ON a.hadm_id = df.hadm_id AND a.subject_id = df.subject_id
  WHERE p.gender = 'F'
    AND p.anchor_age BETWEEN 77 AND 87
    AND df.has_hf = 1
    AND df.has_copd = 1
    AND a.admittime IS NOT NULL
    AND a.dischtime IS NOT NULL
    AND a.dischtime > a.admittime
)

SELECT
  COUNT(1) AS n_admissions,
  ROUND(STDDEV_SAMP(los_days), 3) AS sd_los_days
FROM cohort;