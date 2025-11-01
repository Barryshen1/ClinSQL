WITH cohort AS (
  SELECT
    a.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    a.hospital_expire_flag,
    DATE_DIFF(a.dischtime, a.admittime, DAY) AS los_days
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON a.subject_id = p.subject_id
  WHERE
    p.gender = 'F'
    AND p.anchor_age BETWEEN 80 AND 90
    -- At least one acute decompensated heart failure diagnosis (ICD-10)
    AND EXISTS (
      SELECT 1
      FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
      JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` diag
        ON d.icd_code = diag.icd_code
       AND d.icd_version = diag.icd_version
      WHERE
        d.hadm_id = a.hadm_id
        AND d.icd_version = 10
        AND LOWER(diag.long_title) LIKE '%acute%'
        AND LOWER(diag.long_title) LIKE '%heart failure%'
    )
),

-- Assign LOS bins
cohort_binned AS (
  SELECT
    *,
    CASE
      WHEN los_days BETWEEN 1 AND 3 THEN '1–3'
      WHEN los_days BETWEEN 4 AND 7 THEN '4–7'
      ELSE '>=8'
    END AS los_bin
  FROM cohort
),

-- Aggregate counts and compute mortality rate + 95% CI
mortality_stats AS (
  SELECT
    los_bin,
    COUNT(*)                     AS n,
    SUM(hospital_expire_flag)    AS deaths,
    SAFE_DIVIDE(SUM(hospital_expire_flag), COUNT(*)) AS p
  FROM cohort_binned
  GROUP BY los_bin
),

-- Compute median time-to-death among those who died in each bin
median_time_to_death AS (
  SELECT
    los_bin,
    -- APPROX_QUANTILES ignores NULLs, so we only feed in los_days for decedents
    APPROX_QUANTILES(los_days, 2)[OFFSET(1)] AS median_time_to_death
  FROM cohort_binned
  WHERE hospital_expire_flag = 1
  GROUP BY los_bin
)

SELECT
  m.los_bin AS los_category,
  m.n,
  m.deaths,
  ROUND(100 * m.p, 2) AS mortality_pct,
  ROUND(100 * (m.p - 1.96 * SQRT(m.p * (1 - m.p) / m.n)), 2) AS ci_lower_pct,
  ROUND(100 * (m.p + 1.96 * SQRT(m.p * (1 - m.p) / m.n)), 2) AS ci_upper_pct,
  mt.median_time_to_death
FROM mortality_stats m
LEFT JOIN median_time_to_death mt
  ON m.los_bin = mt.los_bin
ORDER BY
  CASE m.los_bin
    WHEN '1–3' THEN 1
    WHEN '4–7' THEN 2
    ELSE 3
  END;