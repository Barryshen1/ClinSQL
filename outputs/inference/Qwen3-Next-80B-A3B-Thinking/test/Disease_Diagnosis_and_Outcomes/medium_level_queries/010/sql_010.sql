WITH cohort AS (
  SELECT
    a.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    a.hospital_expire_flag,
    p.anchor_age,
    p.anchor_year,
    p.gender,
    p.anchor_age + (EXTRACT(YEAR FROM a.admittime) - p.anchor_year) AS age_at_admission,
    (
      SELECT COUNT(*)
      FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
      WHERE d.subject_id = a.subject_id
        AND d.hadm_id = a.hadm_id
        AND NOT (
          (d.icd_version = 9 AND d.icd_code LIKE '410%')
          OR (d.icd_version = 10 AND d.icd_code LIKE 'I21%')
        )
    ) AS comorbidity_count,
    EXISTS (
      SELECT 1
      FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
      WHERE d.subject_id = a.subject_id
        AND d.hadm_id = a.hadm_id
        AND (
          (d.icd_version = 9 AND d.icd_code = '785.5')
          OR (d.icd_version = 10 AND d.icd_code LIKE 'R57%')
          OR (d.icd_version = 9 AND d.icd_code = '518.81')
          OR (d.icd_version = 10 AND d.icd_code IN ('J96.00', 'J96.01', 'J96.20', 'J96.21'))
        )
    ) AS has_shock_or_respiratory_failure
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON a.subject_id = p.subject_id
  WHERE p.gender = 'M'
    AND p.anchor_age + (EXTRACT(YEAR FROM a.admittime) - p.anchor_year) BETWEEN 78 AND 88
),
filtered_cohort AS (
  SELECT *
  FROM cohort
  WHERE NOT has_shock_or_respiratory_failure
    AND EXISTS (
      SELECT 1
      FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
      WHERE d.subject_id = cohort.subject_id
        AND d.hadm_id = cohort.hadm_id
        AND (
          (d.icd_version = 9 AND d.icd_code LIKE '410%')
          OR (d.icd_version = 10 AND d.icd_code LIKE 'I21%')
        )
    )
),
los_cohort AS (
  SELECT
    *,
    DATE_DIFF(dischtime, admittime, DAY) AS los_days
  FROM filtered_cohort
),
los_quartiles AS (
  SELECT
    *,
    NTILE(4) OVER (ORDER BY los_days) AS los_quartile
  FROM los_cohort
),
comorbidity_cohort AS (
  SELECT
    *,
    CASE
      WHEN comorbidity_count = 0 THEN 'low'
      WHEN comorbidity_count BETWEEN 1 AND 2 THEN 'med'
      ELSE 'high'
    END AS comorbidity_burden
  FROM los_quartiles
),
mortality_rates AS (
  SELECT
    los_quartile,
    comorbidity_burden,
    COUNT(*) AS total_patients,
    SUM(CAST(hospital_expire_flag AS INT64)) AS deaths,
    SUM(CAST(hospital_expire_flag AS INT64)) * 1.0 / COUNT(*) AS mortality_rate,
    (SUM(CAST(hospital_expire_flag AS INT64)) * 1.0 / COUNT(*)) - 1.96 * SQRT(
      (SUM(CAST(hospital_expire_flag AS INT64)) * 1.0 / COUNT(*)) * 
      (1 - SUM(CAST(hospital_expire_flag AS INT64)) * 1.0 / COUNT(*)) / 
      COUNT(*)
    ) AS lower_ci,
    (SUM(CAST(hospital_expire_flag AS INT64)) * 1.0 / COUNT(*)) + 1.96 * SQRT(
      (SUM(CAST(hospital_expire_flag AS INT64)) * 1.0 / COUNT(*)) * 
      (1 - SUM(CAST(hospital_expire_flag AS INT64)) * 1.0 / COUNT(*)) / 
      COUNT(*)
    ) AS upper_ci
  FROM comorbidity_cohort
  GROUP BY los_quartile, comorbidity_burden
),
comorbidity_prevalence AS (
  SELECT
    SUM(CASE WHEN ckd THEN 1 ELSE 0 END) * 1.0 / COUNT(*) AS ckd_prevalence,
    SUM(CASE WHEN diabetes THEN 1 ELSE 0 END) * 1.0 / COUNT(*) AS diabetes_prevalence
  FROM (
    SELECT
      c.*,
      EXISTS (
        SELECT 1
        FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
        WHERE d.subject_id = c.subject_id
          AND d.hadm_id = c.hadm_id
          AND (
            (d.icd_version = 9 AND d.icd_code LIKE '585%')
            OR (d.icd_version = 10 AND d.icd_code LIKE 'N18%')
          )
      ) AS ckd,
      EXISTS (
        SELECT 1
        FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
        WHERE d.subject_id = c.subject_id
          AND d.hadm_id = c.hadm_id
          AND (
            (d.icd_version = 9 AND d.icd_code LIKE '250%')
            OR (d.icd_version = 10 AND (d.icd_code LIKE 'E10%' OR d.icd_code LIKE 'E11%'))
          )
      ) AS diabetes
    FROM comorbidity_cohort c
  )
)
SELECT
  'Mortality by LOS Quartile and Comorbidity Burden' AS metric,
  los_quartile,
  comorbidity_burden,
  total_patients,
  deaths,
  mortality_rate,
  lower_ci,
  upper_ci
FROM mortality_rates
UNION ALL
SELECT
  'CKD Prevalence' AS metric,
  NULL,
  NULL,
  NULL,
  NULL,
  ckd_prevalence,
  NULL,
  NULL
FROM comorbidity_prevalence
UNION ALL
SELECT
  'Diabetes Prevalence' AS metric,
  NULL,
  NULL,
  NULL,
  NULL,
  diabetes_prevalence,
  NULL,
  NULL
FROM comorbidity_prevalence;