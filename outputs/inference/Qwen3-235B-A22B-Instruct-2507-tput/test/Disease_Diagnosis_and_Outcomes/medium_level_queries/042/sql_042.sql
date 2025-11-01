WITH

-- Define ICD codes for conditions
ami_codes AS (
  SELECT icd_code, icd_version
  FROM `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses`
  WHERE (
    (icd_version = 9 AND icd_code LIKE '410%')
    OR (icd_version = 10 AND (icd_code LIKE 'I21%' OR icd_code LIKE 'I22%'))
  )
),

exclusion_codes AS (
  SELECT icd_code, icd_version
  FROM `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses`
  WHERE (
    -- Shock: ICD-9 785.5x, ICD-10 R57.x
    (icd_version = 9 AND icd_code LIKE '785.5%')
    OR (icd_version = 10 AND icd_code LIKE 'R57%')
    -- Respiratory failure: ICD-9 518.81, 518.82, 518.85; ICD-10 J96.x
    OR (icd_version = 9 AND icd_code IN ('51881', '51882', '51885'))
    OR (icd_version = 10 AND icd_code LIKE 'J96%')
  )
),

-- Patients with AMI
ami_patients AS (
  SELECT DISTINCT di.subject_id, di.hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` di
  INNER JOIN ami_codes ac
    ON di.icd_code = ac.icd_code AND di.icd_version = ac.icd_version
),

-- Patients with exclusion diagnoses (shock or respiratory failure)
excluded_patients AS (
  SELECT DISTINCT di.subject_id
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` di
  INNER JOIN exclusion_codes ec
    ON di.icd_code = ec.icd_code AND di.icd_version = ec.icd_version
),

-- Get patient demographics and age at admission
cohort AS (
  SELECT
    p.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    a.discharge_location,
    a.hospital_expire_flag,
    -- Calculate age at admission using EXTRACT
    (EXTRACT(YEAR FROM a.admittime) - p.anchor_year + p.anchor_age) AS age_at_admit
  FROM `physionet-data.mimiciv_3_1_hosp.patients` p
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a
    ON p.subject_id = a.subject_id
  INNER JOIN ami_patients am
    ON a.hadm_id = am.hadm_id
  WHERE p.gender = 'M'
    AND (EXTRACT(YEAR FROM a.admittime) - p.anchor_year + p.anchor_age) BETWEEN 69 AND 79
    AND a.dischtime IS NOT NULL
    AND a.admittime IS NOT NULL
    AND p.subject_id NOT IN (SELECT subject_id FROM excluded_patients)
),

-- Add LOS and categorize
cohort_los AS (
  SELECT
    *,
    DATETIME_DIFF(dischtime, admittime, DAY) AS los_days
  FROM cohort
  WHERE dischtime >= admittime  -- Valid LOS
),

-- Final categorization
cohort_final AS (
  SELECT
    *,
    CASE
      WHEN los_days BETWEEN 1 AND 3 THEN '1-3 days'
      WHEN los_days BETWEEN 4 AND 7 THEN '4-7 days'
      WHEN los_days >= 8 THEN '>=8 days'
      ELSE NULL
    END AS los_group
  FROM cohort_los
  WHERE los_days >= 1  -- Minimum 1 day stay
),

-- Pre-aggregate discharge destinations by LOS group
discharge_summary AS (
  SELECT
    los_group,
    discharge_location,
    COUNT(*) AS count_loc
  FROM cohort_final
  WHERE los_group IS NOT NULL
  GROUP BY los_group, discharge_location
),

-- Aggregate discharge destinations into a string per LOS group
discharge_agg AS (
  SELECT
    los_group,
    STRING_AGG(
      CONCAT(discharge_location, ': ', CAST(count_loc AS STRING)),
      '; '
      ORDER BY discharge_location
    ) AS discharge_destinations_counts
  FROM discharge_summary
  GROUP BY los_group
)

-- Final output: group by LOS group with mortality and median LOS
SELECT
  cf.los_group,
  -- Mortality %
  ROUND(AVG(cf.hospital_expire_flag) * 100, 2) AS mortality_percent,
  -- Median LOS in days
  APPROX_QUANTILES(cf.los_days, 100)[OFFSET(50)] AS median_los_days,
  -- Discharge destinations with counts
  da.discharge_destinations_counts
FROM cohort_final cf
JOIN discharge_agg da ON cf.los_group = da.los_group
WHERE cf.los_group IS NOT NULL
GROUP BY cf.los_group, da.discharge_destinations_counts
ORDER BY
  CASE cf.los_group
    WHEN '1-3 days' THEN 1
    WHEN '4-7 days' THEN 2
    WHEN '>=8 days' THEN 3
  END;