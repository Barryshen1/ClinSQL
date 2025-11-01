WITH patients AS (
  SELECT subject_id, gender, anchor_age
  FROM `physionet-data.mimiciv_3_1_hosp.patients`
  WHERE gender = 'M' AND anchor_age BETWEEN 50 AND 60
),
admissions AS (
  SELECT a.subject_id, a.hadm_id, a.admittime, a.dischtime, a.deathtime, a.hospital_expire_flag
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  INNER JOIN patients p ON a.subject_id = p.subject_id
  WHERE a.dischtime > a.admittime
),
sepsis_hadm AS (
  SELECT DISTINCT subject_id, hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd`
  WHERE (
    (icd_version = 9 AND (icd_code LIKE '038.%' OR icd_code LIKE '670.2%' OR icd_code LIKE '670.3%'))
    OR
    (icd_version = 10 AND (icd_code LIKE 'A40.%' OR icd_code LIKE 'A41.%'))
  )
),
shock_hadm AS (
  SELECT DISTINCT subject_id, hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd`
  WHERE (
    (icd_version = 9 AND icd_code = '785.52')
    OR
    (icd_version = 10 AND icd_code LIKE 'R65.2%')
  )
),
cohort AS (
  SELECT 
    a.*,
    DATE_DIFF(a.dischtime, a.admittime, DAY) AS los_days,
    DATE_DIFF(a.deathtime, a.admittime, DAY) AS ttd_days,
    CASE WHEN DATE_DIFF(a.dischtime, a.admittime, DAY) < 8 THEN '<8' ELSE '>=8' END AS los_group
  FROM admissions a
  INNER JOIN sepsis_hadm s ON a.subject_id = s.subject_id AND a.hadm_id = s.hadm_id
  LEFT JOIN shock_hadm sh ON a.subject_id = sh.subject_id AND a.hadm_id = sh.hadm_id
  WHERE sh.hadm_id IS NULL
),
agg AS (
  SELECT 
    los_group,
    COUNT(*) AS n,
    SUM(hospital_expire_flag) AS deaths,
    APPROX_QUANTILES(ttd_days, 2)[OFFSET(1)] AS median_ttd
  FROM cohort
  GROUP BY los_group
)
SELECT 
  los_group,
  n,
  deaths,
  ROUND(SAFE_DIVIDE(deaths, n) * 100, 2) AS mortality_pct,
  ROUND(
    (
      (
        (SAFE_DIVIDE(deaths, n) + (1.96 * 1.96) / (2 * n)) / (1 + (1.96 * 1.96) / n)
      ) -
      (
        1.96 * SQRT(SAFE_DIVIDE(deaths, n) * (1 - SAFE_DIVIDE(deaths, n)) / n + (1.96 * 1.96) / (4 * n * n))
        / (1 + (1.96 * 1.96) / n)
      )
    ) * 100,
    2
  ) AS ci_lower_pct,
  ROUND(
    (
      (
        (SAFE_DIVIDE(deaths, n) + (1.96 * 1.96) / (2 * n)) / (1 + (1.96 * 1.96) / n)
      ) +
      (
        1.96 * SQRT(SAFE_DIVIDE(deaths, n) * (1 - SAFE_DIVIDE(deaths, n)) / n + (1.96 * 1.96) / (4 * n * n))
        / (1 + (1.96 * 1.96) / n)
      )
    ) * 100,
    2
  ) AS ci_upper_pct,
  ROUND(median_ttd, 1) AS median_ttd_days
FROM agg
ORDER BY los_group;