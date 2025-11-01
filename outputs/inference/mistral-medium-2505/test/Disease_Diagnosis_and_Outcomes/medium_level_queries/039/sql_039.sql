WITH
-- Get female patients aged 66-76
female_patients AS (
  SELECT
    subject_id,
    gender,
    anchor_age,
    anchor_year,
    dod
  FROM
    `physionet-data.mimiciv_3_1_hosp.patients`
  WHERE
    gender = 'F'
    AND anchor_age BETWEEN 66 AND 76
),

-- Get AMI admissions
ami_admissions AS (
  SELECT
    a.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    a.deathtime,
    a.hospital_expire_flag,
    a.admission_type,
    TIMESTAMP_DIFF(a.dischtime, a.admittime, DAY) AS los_days
  FROM
    `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN
    `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
  ON
    a.hadm_id = d.hadm_id
  JOIN
    female_patients p
  ON
    a.subject_id = p.subject_id
  WHERE
    d.icd_code LIKE 'I21.%'
    AND d.icd_version = 10
),

-- Exclude patients with initial shock or respiratory failure
excluded_admissions AS (
  SELECT DISTINCT
    a.hadm_id
  FROM
    ami_admissions a
  JOIN
    `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
  ON
    a.hadm_id = d.hadm_id
  WHERE
    (d.icd_code LIKE 'R57.%' OR d.icd_code LIKE 'J96.%') -- Shock and respiratory failure codes
    AND d.icd_version = 10
    AND d.seq_num = 1 -- Primary diagnosis
),

-- Final cohort after exclusions
cohort AS (
  SELECT
    a.*
  FROM
    ami_admissions a
  WHERE
    a.hadm_id NOT IN (SELECT hadm_id FROM excluded_admissions)
),

-- Categorize LOS and admission type
cohort_with_categories AS (
  SELECT
    hadm_id,
    CASE
      WHEN los_days BETWEEN 1 AND 3 THEN '1-3 days'
      WHEN los_days BETWEEN 4 AND 7 THEN '4-7 days'
      WHEN los_days >= 8 THEN '≥8 days'
      ELSE 'Other'
    END AS los_category,
    CASE
      WHEN admission_type = 'EMERGENCY' THEN 'Emergent'
      ELSE 'Non-emergent'
    END AS admission_type_category,
    hospital_expire_flag,
    TIMESTAMP_DIFF(deathtime, admittime, DAY) AS time_to_death_days
  FROM
    cohort
  WHERE
    los_days IS NOT NULL
)

-- Final aggregation
SELECT
  los_category,
  admission_type_category,
  COUNT(*) AS total_admissions,
  SUM(CASE WHEN hospital_expire_flag = 1 THEN 1 ELSE 0 END) AS deaths,
  ROUND(SUM(CASE WHEN hospital_expire_flag = 1 THEN 1 ELSE 0 END) / COUNT(*) * 100, 2) AS mortality_percentage,
  APPROX_QUANTILES(CASE WHEN hospital_expire_flag = 1 THEN time_to_death_days ELSE NULL END, 100)[OFFSET(50)] AS median_time_to_death_days
FROM
  cohort_with_categories
GROUP BY
  los_category,
  admission_type_category
ORDER BY
  los_category,
  admission_type_category;