WITH cohort_admissions AS (
  SELECT
    a.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    a.hospital_expire_flag,
    p.gender,
    p.anchor_age,
    TIMESTAMP_DIFF(a.dischtime, a.admittime, DAY) AS los_days
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON a.subject_id = p.subject_id
  WHERE p.gender = 'F'
    AND p.anchor_age BETWEEN 52 AND 62
    AND a.admittime IS NOT NULL
    AND a.dischtime IS NOT NULL
),
diag_flags AS (
  -- per-admission flags and a simple comorbidity count (excluding stroke codes)
  SELECT
    ca.subject_id,
    ca.hadm_id,
    ca.admittime,
    ca.dischtime,
    ca.hospital_expire_flag,
    ca.gender,
    ca.anchor_age,
    ca.los_days,
    MAX(CASE
          WHEN (di.icd_version = 9 AND REGEXP_CONTAINS(di.icd_code, r'^(433|434|436)'))
            OR (di.icd_version = 10 AND REGEXP_CONTAINS(di.icd_code, r'^I63'))
          THEN 1 ELSE 0 END) AS has_ischemic,
    MAX(CASE
          WHEN (di.icd_version = 9 AND REGEXP_CONTAINS(di.icd_code, r'^(430|431|432)'))
            OR (di.icd_version = 10 AND REGEXP_CONTAINS(di.icd_code, r'^I6[0-2]'))
          THEN 1 ELSE 0 END) AS has_hemorrhagic,
    MAX(CASE
          WHEN (di.icd_version = 9 AND REGEXP_CONTAINS(di.icd_code, r'^585'))
            OR (di.icd_version = 10 AND REGEXP_CONTAINS(di.icd_code, r'^N18'))
          THEN 1 ELSE 0 END) AS has_ckd,
    MAX(CASE
          WHEN (di.icd_version = 9 AND REGEXP_CONTAINS(di.icd_code, r'^250'))
            OR (di.icd_version = 10 AND REGEXP_CONTAINS(di.icd_code, r'^E1[0-4]'))
          THEN 1 ELSE 0 END) AS has_dm,
    COUNT(DISTINCT CASE
        WHEN NOT (
             (di.icd_version = 9 AND REGEXP_CONTAINS(di.icd_code, r'^(433|434|436|430|431|432)'))
          OR (di.icd_version = 10 AND REGEXP_CONTAINS(di.icd_code, r'^(I63|I6[0-2])'))
        ) THEN di.icd_code ELSE NULL END) AS comorbidity_count
  FROM cohort_admissions ca
  LEFT JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` di
    ON ca.hadm_id = di.hadm_id
  GROUP BY
    ca.subject_id, ca.hadm_id, ca.admittime, ca.dischtime, ca.hospital_expire_flag,
    ca.gender, ca.anchor_age, ca.los_days
),
cohort_stroke AS (
  -- label admissions as ischemic or hemorrhagic; exclude mixed (both types) by leaving NULL
  SELECT
    df.*,
    CASE
      WHEN has_ischemic = 1 AND has_hemorrhagic = 0 THEN 'Ischemic'
      WHEN has_hemorrhagic = 1 AND has_ischemic = 0 THEN 'Hemorrhagic'
      ELSE NULL
    END AS stroke_type
  FROM diag_flags df
),
stroke_only AS (
  -- keep only mutually exclusive ischemic OR hemorrhagic admissions
  SELECT * FROM cohort_stroke WHERE stroke_type IS NOT NULL
),
with_tertile AS (
  -- compute comorbidity tertile across the cohort (1 = lowest comorbidity_count)
  SELECT
    s.*,
    NTILE(3) OVER (ORDER BY comorbidity_count) AS comorb_tertile
  FROM stroke_only s
)
SELECT
  stroke_type,
  comorb_tertile,
  COUNT(*) AS n_patients,
  ROUND(100.0 * SUM(hospital_expire_flag) / COUNT(*), 2) AS mortality_pct,
  -- approximate median LOS (days)
  APPROX_QUANTILES(los_days, 2)[OFFSET(1)] AS median_los_days,
  ROUND(100.0 * SUM(CASE WHEN los_days < 8 THEN 1 ELSE 0 END) / COUNT(*), 2) AS pct_los_lt_8,
  ROUND(100.0 * SUM(CASE WHEN los_days >= 8 THEN 1 ELSE 0 END) / COUNT(*), 2) AS pct_los_ge_8,
  ROUND(100.0 * SUM(has_ckd) / COUNT(*), 2) AS ckd_pct,
  ROUND(100.0 * SUM(has_dm) / COUNT(*), 2) AS diabetes_pct
FROM with_tertile
GROUP BY stroke_type, comorb_tertile
ORDER BY stroke_type, comorb_tertile;