WITH diag_flags AS (
  -- For each hospital admission, flag presence of heart failure, CKD, and diabetes
  SELECT
    d.hadm_id,
    MAX(CASE WHEN REGEXP_CONTAINS(LOWER(dd.long_title), r'heart failure') THEN 1 ELSE 0 END) AS has_hf,
    MAX(CASE WHEN REGEXP_CONTAINS(LOWER(dd.long_title), r'(chronic (kidney|renal)|end.?stage|stage [1-5])') THEN 1 ELSE 0 END) AS has_ckd,
    MAX(CASE WHEN REGEXP_CONTAINS(LOWER(dd.long_title), r'\bdiabetes\b') THEN 1 ELSE 0 END) AS has_dm
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
  JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` dd
    ON d.icd_code = dd.icd_code AND d.icd_version = dd.icd_version
  GROUP BY d.hadm_id
),

cohort AS (
  -- Admissions for male patients age 68-78 with computed LOS and linked diagnosis flags
  SELECT
    a.subject_id,
    a.hadm_id,
    p.gender,
    p.anchor_age,
    a.admittime,
    a.dischtime,
    a.hospital_expire_flag,
    TIMESTAMP_DIFF(a.dischtime, a.admittime, SECOND) / 86400.0 AS los_days,
    COALESCE(df.has_hf, 0) AS has_hf,
    COALESCE(df.has_ckd, 0) AS has_ckd,
    COALESCE(df.has_dm, 0) AS has_dm
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON a.subject_id = p.subject_id
  LEFT JOIN diag_flags df
    ON a.hadm_id = df.hadm_id
  WHERE p.gender = 'M'
    AND p.anchor_age BETWEEN 68 AND 78
    AND a.admittime IS NOT NULL
    AND a.dischtime IS NOT NULL
)

SELECT
  CASE WHEN los_days < 8 THEN '<8 days' ELSE '>=8 days' END AS los_group,
  COUNT(*) AS n_admissions,
  SUM(hospital_expire_flag) AS n_deaths,
  ROUND(100.0 * SAFE_DIVIDE(SUM(hospital_expire_flag), COUNT(*)), 1) AS pct_inhospital_mortality,
  SUM(has_ckd) AS n_ckd,
  ROUND(100.0 * SAFE_DIVIDE(SUM(has_ckd), COUNT(*)), 1) AS pct_ckd,
  SUM(has_dm) AS n_diabetes,
  ROUND(100.0 * SAFE_DIVIDE(SUM(has_dm), COUNT(*)), 1) AS pct_diabetes
FROM cohort
WHERE has_hf = 1  -- restrict to admissions with heart failure diagnosis
GROUP BY los_group
ORDER BY los_group DESC;