WITH sepsis_cohort AS (
  -- Identify patients with sepsis (excluding septic shock)
  SELECT DISTINCT
    d.subject_id
  FROM
    physionet-data.mimiciv_3_1_hosp.diagnoses_icd d
  JOIN
    physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses dd
    ON d.icd_code = dd.icd_code AND d.icd_version = dd.icd_version
  WHERE
    dd.icd_code IN ('995.91', 'A41.9', 'R65.20')
),
septic_shock_exclude AS (
  -- Exclude patients with any diagnosis of septic shock
  SELECT DISTINCT
    subject_id
  FROM
    physionet-data.mimiciv_3_1_hosp.diagnoses_icd d
  JOIN
    physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses dd
    ON d.icd_code = dd.icd_code AND d.icd_version = dd.icd_version
  WHERE
    dd.icd_code IN ('R65.21')
),
eligible_patients AS (
  -- Filter patients by age and gender
  SELECT
    p.subject_id
  FROM
    physionet-data.mimiciv_3_1_hosp.patients p
  WHERE
    p.gender = 'M'
    AND p.anchor_age BETWEEN 50 AND 60
),
admissions_filtered AS (
  -- Join admissions with eligible patients and sepsis criteria
  SELECT
    a.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    a.deathtime,
    a.hospital_expire_flag,
    DATETIME_DIFF(a.dischtime, a.admittime, DAY) AS los_days
  FROM
    physionet-data.mimiciv_3_1_hosp.admissions a
  JOIN
    eligible_patients ep
    ON a.subject_id = ep.subject_id
  JOIN
    sepsis_cohort sc
    ON a.subject_id = sc.subject_id
  WHERE
    a.subject_id NOT IN (SELECT subject_id FROM septic_shock_exclude)
),
los_stratified AS (
  SELECT
    *,
    CASE
      WHEN los_days < 8 THEN '<8 days'
      ELSE '≥8 days'
    END AS los_group
  FROM
    admissions_filtered
),
mortality_stats AS (
  SELECT
    los_group,
    COUNT(*) AS total,
    SUM(hospital_expire_flag) AS deaths,
    -- Median time-to-death among non-survivors
    APPROX_QUANTILES(
      CASE WHEN hospital_expire_flag = 1 THEN DATETIME_DIFF(deathtime, admittime, DAY) END,
      2
    )[OFFSET(1)] AS median_time_to_death_days
  FROM
    los_stratified
  GROUP BY
    los_group
)
SELECT
  los_group,
  total,
  deaths,
  ROUND(100 * deaths / total, 2) AS mortality_percent,
  ROUND(
    100 * (
      deaths / total - 1.96 * SQRT((deaths / total) * (1 - deaths / total) / total)
    ),
    2
  ) AS ci_lower,
  ROUND(
    100 * (
      deaths / total + 1.96 * SQRT((deaths / total) * (1 - deaths / total) / total)
    ),
    2
  ) AS ci_upper,
  median_time_to_death_days
FROM
  mortality_stats
ORDER BY
  los_group;