WITH base_adm AS (
  SELECT
    a.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    a.hospital_expire_flag,
    DATE_DIFF(a.dischtime, a.admittime, DAY) AS los
  FROM
    `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN
    `physionet-data.mimiciv_3_1_hosp.patients` p
    ON a.subject_id = p.subject_id
  WHERE
    p.gender = 'M'
    AND p.anchor_age BETWEEN 78 AND 88
),
ami_adm AS (
  -- admissions with AMI
  SELECT DISTINCT hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd`
  WHERE
    (icd_version = 9 AND STARTS_WITH(icd_code, '410'))
    OR (icd_version = 10 AND STARTS_WITH(icd_code, 'I21'))
),
exclude_adm AS (
  -- admissions with shock OR respiratory failure
  SELECT DISTINCT hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd`
  WHERE
    (icd_version = 9 AND (
       STARTS_WITH(icd_code, '7855')
       OR STARTS_WITH(icd_code, '5188')
     ))
    OR (icd_version = 10 AND (
       STARTS_WITH(icd_code, 'R57')
       OR STARTS_WITH(icd_code, 'J96')
     ))
),
dx_flags AS (
  -- aggregate comorbidities, CKD, DM flags, count distinct dx per admission
  SELECT
    d.hadm_id,
    COUNT(DISTINCT d.icd_code) 
      - COUNTIF(
          (icd_version = 9 AND STARTS_WITH(icd_code, '410'))
          OR (icd_version = 10 AND STARTS_WITH(icd_code, 'I21'))
        ) 
      AS comorb_count,
    MAX(
      CASE
        WHEN (icd_version = 9 AND STARTS_WITH(icd_code, '585'))
          OR (icd_version = 10 AND STARTS_WITH(icd_code, 'N18'))
        THEN 1 ELSE 0 END
    ) AS ckd_flag,
    MAX(
      CASE
        WHEN (icd_version = 9 AND STARTS_WITH(icd_code, '250'))
          OR (icd_version = 10 AND STARTS_WITH(icd_code, 'E11'))
        THEN 1 ELSE 0 END
    ) AS dm_flag
  FROM
    `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
  GROUP BY hadm_id
),
cohort AS (
  SELECT
    b.subject_id,
    b.hadm_id,
    b.los,
    b.hospital_expire_flag,
    dx.comorb_count,
    CASE
      WHEN dx.comorb_count <= 1 THEN 'low'
      WHEN dx.comorb_count <= 3 THEN 'medium'
      ELSE 'high'
    END AS comorb_burden,
    dx.ckd_flag,
    dx.dm_flag
  FROM base_adm b
  JOIN ami_adm a ON b.hadm_id = a.hadm_id
  LEFT JOIN exclude_adm e ON b.hadm_id = e.hadm_id
  JOIN dx_flags dx ON b.hadm_id = dx.hadm_id
  WHERE e.hadm_id IS NULL
),
quartiles AS (
  SELECT
    *,
    NTILE(4) OVER (ORDER BY los) AS los_quartile
  FROM cohort
)
SELECT
  los_quartile,
  comorb_burden,
  COUNT(*) AS N,
  SUM(hospital_expire_flag) AS deaths,
  SAFE_DIVIDE(SUM(hospital_expire_flag), COUNT(*)) AS mortality_rate,
  -- 95% CI, normal approx
  SAFE_DIVIDE(SUM(hospital_expire_flag), COUNT(*))
    - 1.96 * SQRT(
        SAFE_DIVIDE(SUM(hospital_expire_flag), COUNT(*))
        * SAFE_DIVIDE(
            COUNT(*) - SUM(hospital_expire_flag),
            COUNT(*) * COUNT(*)
          )
      ) AS mortality_ci_lower,
  SAFE_DIVIDE(SUM(hospital_expire_flag), COUNT(*))
    + 1.96 * SQRT(
        SAFE_DIVIDE(SUM(hospital_expire_flag), COUNT(*))
        * SAFE_DIVIDE(
            COUNT(*) - SUM(hospital_expire_flag),
            COUNT(*) * COUNT(*)
          )
      ) AS mortality_ci_upper,
  SAFE_DIVIDE(SUM(ckd_flag), COUNT(*)) AS ckd_prevalence,
  SAFE_DIVIDE(SUM(dm_flag), COUNT(*)) AS dm_prevalence
FROM quartiles
GROUP BY los_quartile, comorb_burden
ORDER BY los_quartile, comorb_burden;