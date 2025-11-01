WITH
-- Step 1: Identify first ICU stays for female patients in the specified age range
first_stays AS (
  SELECT
    p.subject_id,
    i.hadm_id,
    i.stay_id,
    i.intime,
    (p.anchor_age + EXTRACT(YEAR FROM i.intime) - p.anchor_year) AS age_at_icustay,
    ROW_NUMBER() OVER(PARTITION BY p.subject_id ORDER BY i.intime) AS stay_rank
  FROM
    `physionet-data.mimiciv_3_1_hosp.patients` AS p
  INNER JOIN
    `physionet-data.mimiciv_3_1_icu.icustays` AS i
    ON p.subject_id = i.subject_id
  WHERE
    p.gender = 'F'
),

-- Step 2: Identify hospital admissions with a sepsis diagnosis
sepsis_hadms AS (
  SELECT DISTINCT
    hadm_id
  FROM
    `physionet-data.mimiciv_3_1_hosp.diagnoses_icd`
  WHERE
    (icd_version = 9 AND icd_code IN ('99591', '99592', '78552'))
    OR (icd_version = 10 AND (icd_code LIKE 'A40%' OR icd_code LIKE 'A41%' OR icd_code LIKE 'R65.2%'))
),

-- Step 3: Define the Sepsis and Control cohorts from the filtered first stays
cohorts AS (
  SELECT
    fs.subject_id,
    fs.hadm_id,
    fs.stay_id,
    fs.intime,
    CASE
      WHEN sh.hadm_id IS NOT NULL THEN 'Sepsis'
      ELSE 'Control'
    END AS cohort_group
  FROM
    first_stays AS fs
  LEFT JOIN
    sepsis_hadms AS sh
    ON fs.hadm_id = sh.hadm_id
  WHERE
    fs.stay_rank = 1
    AND fs.age_at_icustay BETWEEN 66 AND 76
),

-- Step 4: For the sepsis cohort, count distinct procedures in the first 48 hours
sepsis_proc_counts AS (
  SELECT
    c.subject_id,
    c.hadm_id,
    COUNT(DISTINCT p.icd_code) AS distinct_procedure_count
  FROM
    cohorts AS c
  INNER JOIN
    `physionet-data.mimiciv_3_1_hosp.procedures_icd` AS p
    ON c.hadm_id = p.hadm_id
  WHERE
    c.cohort_group = 'Sepsis'
    -- Captures procedures on the day of ICU admission and the following calendar day
    -- as a proxy for the first 48 hours, given procedures_icd has a DATE type column.
    AND p.chartdate >= DATE(c.intime)
    AND p.chartdate <= DATE_ADD(DATE(c.intime), INTERVAL 1 DAY)
  GROUP BY
    c.subject_id,
    c.hadm_id
),

-- Step 5: Calculate the 90th percentile of the procedure counts for the sepsis cohort
percentile_90_procs AS (
  SELECT
    APPROX_QUANTILES(distinct_procedure_count, 100)[OFFSET(90)] AS percentile_90_procedure_count
  FROM
    sepsis_proc_counts
),

-- Step 6: Calculate LOS and mortality outcomes for both cohorts
cohort_outcomes AS (
  SELECT
    c.cohort_group,
    AVG(DATETIME_DIFF(a.dischtime, a.admittime, HOUR) / 24.0) AS avg_hospital_los_days,
    AVG(a.hospital_expire_flag) AS in_hospital_mortality_rate
  FROM
    cohorts AS c
  INNER JOIN
    `physionet-data.mimiciv_3_1_hosp.admissions` AS a
    ON c.hadm_id = a.hadm_id
  GROUP BY
    c.cohort_group
)

-- Final Step: Combine all metrics into a single summary row
SELECT
  MAX(p90.percentile_90_procedure_count) AS percentile_90_procedure_count,
  MAX(CASE WHEN co.cohort_group = 'Sepsis' THEN co.avg_hospital_los_days END) AS avg_los_sepsis,
  MAX(CASE WHEN co.cohort_group = 'Sepsis' THEN co.in_hospital_mortality_rate END) AS mortality_rate_sepsis,
  MAX(CASE WHEN co.cohort_group = 'Control' THEN co.avg_hospital_los_days END) AS avg_los_control,
  MAX(CASE WHEN co.cohort_group = 'Control' THEN co.in_hospital_mortality_rate END) AS mortality_rate_control
FROM
  cohort_outcomes AS co,
  percentile_90_procs AS p90;