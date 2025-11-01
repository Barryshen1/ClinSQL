WITH
-- 1. Identify female patients aged 62-72 at admission
female_62_72 AS (
  SELECT
    p.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    a.hospital_expire_flag
  FROM
    `physionet-data.mimiciv_3_1_hosp.patients` p
    JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a
      ON p.subject_id = a.subject_id
  WHERE
    p.gender = 'F'
    AND p.anchor_age BETWEEN 62 AND 72
),

-- 2. Identify AMI admissions
ami_admissions AS (
  SELECT DISTINCT
    d.subject_id,
    d.hadm_id
  FROM
    `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
  WHERE
    (
      -- ICD-10: I21.x, I22.x
      (d.icd_version = 10 AND (SAFE_CAST(SUBSTR(d.icd_code, 1, 3) AS STRING) IN ('I21', 'I22')))
      OR
      -- ICD-9: 410.x
      (d.icd_version = 9 AND (SAFE_CAST(SUBSTR(d.icd_code, 1, 3) AS STRING) = '410'))
    )
),

-- 3. Identify admissions with shock or respiratory failure
shock_resp_fail AS (
  SELECT DISTINCT
    d.subject_id,
    d.hadm_id
  FROM
    `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
  WHERE
    (
      -- Shock ICD-10: R57.x
      (d.icd_version = 10 AND SAFE_CAST(SUBSTR(d.icd_code, 1, 3) AS STRING) = 'R57')
      OR
      -- Shock ICD-9: 785.5x
      (d.icd_version = 9 AND SAFE_CAST(SUBSTR(d.icd_code, 1, 5) AS STRING) = '785.5')
      OR
      -- Respiratory failure ICD-10: J96.x
      (d.icd_version = 10 AND SAFE_CAST(SUBSTR(d.icd_code, 1, 3) AS STRING) = 'J96')
      OR
      -- Respiratory failure ICD-9: 518.81, 518.82, 518.84
      (d.icd_version = 9 AND d.icd_code IN ('51881', '51882', '51884'))
    )
),

-- 4. Identify CKD admissions
ckd_admissions AS (
  SELECT DISTINCT
    d.subject_id,
    d.hadm_id
  FROM
    `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
  WHERE
    (
      -- CKD ICD-10: N18.x
      (d.icd_version = 10 AND SAFE_CAST(SUBSTR(d.icd_code, 1, 3) AS STRING) = 'N18')
      OR
      -- CKD ICD-9: 585.x
      (d.icd_version = 9 AND SAFE_CAST(SUBSTR(d.icd_code, 1, 3) AS STRING) = '585')
    )
),

-- 5. Identify diabetes admissions
diabetes_admissions AS (
  SELECT DISTINCT
    d.subject_id,
    d.hadm_id
  FROM
    `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
  WHERE
    (
      -- Diabetes ICD-10: E10-E14
      (d.icd_version = 10 AND SAFE_CAST(SUBSTR(d.icd_code, 1, 3) AS STRING) IN ('E10', 'E11', 'E12', 'E13', 'E14'))
      OR
      -- Diabetes ICD-9: 250.x
      (d.icd_version = 9 AND SAFE_CAST(SUBSTR(d.icd_code, 1, 3) AS STRING) = '250')
    )
),

-- 6. Build final cohort: female 62-72, AMI, exclude shock/resp failure
cohort AS (
  SELECT
    f.subject_id,
    f.hadm_id,
    f.admittime,
    f.dischtime,
    f.hospital_expire_flag,
    -- LOS in days
    SAFE_CAST(TIMESTAMP_DIFF(f.dischtime, f.admittime, DAY) AS INT64) AS los_days,
    -- CKD flag
    CASE WHEN ckd.subject_id IS NOT NULL THEN 1 ELSE 0 END AS has_ckd,
    -- Diabetes flag
    CASE WHEN diab.subject_id IS NOT NULL THEN 1 ELSE 0 END AS has_diabetes
  FROM
    female_62_72 f
    INNER JOIN ami_admissions ami
      ON f.subject_id = ami.subject_id AND f.hadm_id = ami.hadm_id
    LEFT JOIN shock_resp_fail srf
      ON f.subject_id = srf.subject_id AND f.hadm_id = srf.hadm_id
    LEFT JOIN ckd_admissions ckd
      ON f.subject_id = ckd.subject_id AND f.hadm_id = ckd.hadm_id
    LEFT JOIN diabetes_admissions diab
      ON f.subject_id = diab.subject_id AND f.hadm_id = diab.hadm_id
  WHERE
    srf.subject_id IS NULL -- exclude shock/resp failure
),

-- 7. Aggregate by LOS group
agg AS (
  SELECT
    CASE WHEN los_days <= 5 THEN '<=5 days' ELSE '>5 days' END AS los_group,
    COUNT(*) AS n_admissions,
    SUM(CASE WHEN hospital_expire_flag = 1 THEN 1 ELSE 0 END) AS n_deaths,
    SUM(has_ckd) AS n_ckd,
    SUM(has_diabetes) AS n_diabetes,
    ROUND(SUM(CASE WHEN hospital_expire_flag = 1 THEN 1 ELSE 0 END) / COUNT(*) * 100, 2) AS mortality_rate_pct,
    ROUND(SUM(has_ckd) / COUNT(*) * 100, 2) AS ckd_prevalence_pct,
    ROUND(SUM(has_diabetes) / COUNT(*) * 100, 2) AS diabetes_prevalence_pct
  FROM
    cohort
  GROUP BY
    los_group
)

-- 8. Final output with absolute and relative mortality difference
SELECT
  a.los_group,
  a.n_admissions,
  a.mortality_rate_pct,
  a.ckd_prevalence_pct,
  a.diabetes_prevalence_pct,
  -- For difference calculations, use window functions
  ROUND(
    a.mortality_rate_pct
    - FIRST_VALUE(a.mortality_rate_pct) OVER (ORDER BY a.los_group DESC), 2
  ) AS absolute_mortality_diff_pct,
  ROUND(
    CASE WHEN FIRST_VALUE(a.mortality_rate_pct) OVER (ORDER BY a.los_group DESC) > 0
      THEN a.mortality_rate_pct / FIRST_VALUE(a.mortality_rate_pct) OVER (ORDER BY a.los_group DESC)
      ELSE NULL END, 2
  ) AS relative_mortality_diff
FROM
  agg a
ORDER BY
  CASE WHEN a.los_group = '<=5 days' THEN 1 ELSE 2 END
;