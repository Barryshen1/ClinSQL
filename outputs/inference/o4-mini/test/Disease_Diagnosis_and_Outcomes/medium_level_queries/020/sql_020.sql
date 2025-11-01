WITH sepsis_admissions AS (
  -- Identify admissions with sepsis (excluding septic shock) in the target age/gender group
  SELECT DISTINCT
    a.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    a.deathtime,
    a.hospital_expire_flag,
    p.anchor_age,
    p.gender
  FROM
    `physionet-data.mimiciv_3_1_hosp.admissions` a
    JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
      ON a.subject_id = p.subject_id
    JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` di
      ON a.subject_id = di.subject_id
      AND a.hadm_id = di.hadm_id
    JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` dd
      ON di.icd_code = dd.icd_code
      AND di.icd_version = dd.icd_version
  WHERE
    p.gender = 'M'
    AND p.anchor_age BETWEEN 86 AND 96
    AND LOWER(dd.long_title) LIKE '%sepsis%'
    AND LOWER(dd.long_title) NOT LIKE '%septic shock%'
),
admission_metrics AS (
  -- Compute LOS, mortality, and days to death
  SELECT
    sa.*,
    DATE_DIFF(sa.dischtime, sa.admittime, DAY) AS los_days,
    sa.hospital_expire_flag AS mortality,
    CASE
      WHEN sa.deathtime IS NOT NULL
      THEN DATE_DIFF(sa.deathtime, sa.admittime, DAY)
      ELSE NULL
    END AS days_to_death
  FROM sepsis_admissions sa
),
admission_with_icu AS (
  -- Determine whether patient was in ICU during first 24h
  SELECT
    am.*,
    CASE
      WHEN EXISTS (
        SELECT 1
        FROM `physionet-data.mimiciv_3_1_icu.icustays` ic
        WHERE ic.subject_id = am.subject_id
          AND ic.hadm_id = am.hadm_id
          AND ic.intime < am.admittime + INTERVAL 1 DAY
          AND ic.outtime > am.admittime
      ) THEN 1
      ELSE 0
    END AS icu_day1
  FROM admission_metrics am
),
binned AS (
  -- Assign LOS buckets
  SELECT
    icu_day1,
    CASE
      WHEN los_days <= 3 THEN '≤3'
      WHEN los_days BETWEEN 4 AND 6 THEN '4–6'
      WHEN los_days BETWEEN 7 AND 10 THEN '7–10'
      ELSE '>10'
    END AS los_bucket,
    mortality,
    days_to_death
  FROM admission_with_icu
)
-- Final aggregation
SELECT
  los_bucket,
  icu_day1,
  COUNT(*) AS n_admissions,
  ROUND(100.0 * SUM(mortality) / COUNT(*), 1) AS mortality_pct,
  -- median days_to_death among those who died
  APPROX_QUANTILES(days_to_death, 2)[OFFSET(1)] AS median_days_to_death
FROM binned
GROUP BY los_bucket, icu_day1
ORDER BY
  -- Ensure logical bucket order
  CASE los_bucket
    WHEN '≤3' THEN 1
    WHEN '4–6' THEN 2
    WHEN '7–10' THEN 3
    WHEN '>10' THEN 4
  END,
  icu_day1;