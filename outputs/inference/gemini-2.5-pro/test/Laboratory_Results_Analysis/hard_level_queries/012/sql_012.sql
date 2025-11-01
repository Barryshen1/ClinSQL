with Acute Myocardial Infarction (AMI).
-- It finds the 75th percentile of this score for the AMI cohort and compares the cohort's
-- average number of critical labs, length of stay (LOS), and mortality rate
-- to the general inpatient population.

WITH
-- Step 1: Find all ICD codes related to Acute Myocardial Infarction (AMI).
ami_icd AS (
  SELECT
    icd_code,
    icd_version
  FROM
    `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses`
  WHERE
    REGEXP_CONTAINS(LOWER(long_title), 'acute myocardial infarction')
),

-- Step 2: Identify the hospital admissions (hadm_id) for the specific AMI cohort.
-- Cohort criteria: Male, aged 44-54 at admission, with an AMI diagnosis.
ami_cohort_hadms AS (
  SELECT DISTINCT
    dx.hadm_id
  FROM
    `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` AS dx
  INNER JOIN
    ami_icd
    ON dx.icd_code = ami_icd.icd_code AND dx.icd_version = ami_icd.icd_version
  INNER JOIN
    `physionet-data.mimiciv_3_1_hosp.admissions` AS adm
    ON dx.hadm_id = adm.hadm_id
  INNER JOIN
    `physionet-data.mimiciv_3_1_hosp.patients` AS pat
    ON dx.subject_id = pat.subject_id
  WHERE
    pat.gender = 'M'
    AND (pat.anchor_age + EXTRACT(YEAR FROM adm.admittime) - pat.anchor_year) BETWEEN 44 AND 54
),

-- Step 3: Categorize all hospital admissions into one of two groups for comparison using an efficient LEFT JOIN.
all_cohorts AS (
  SELECT
    adm.hadm_id,
    adm.admittime,
    adm.dischtime,
    adm.hospital_expire_flag,
    CASE
      WHEN ami_cohort.hadm_id IS NOT NULL
      THEN 'AMI (Male, 44-54)'
      ELSE 'General Inpatient'
    END AS cohort_group
  FROM
    `physionet-data.mimiciv_3_1_hosp.admissions` AS adm
  LEFT JOIN
    ami_cohort_hadms AS ami_cohort
    ON adm.hadm_id = ami_cohort.hadm_id
),

-- Step 4: Calculate the "lab instability score" for each admission.
-- The score is the count of abnormal labs in the first 72 hours.
-- Carry forward columns needed for later calculations to avoid a redundant join.
lab_instability_scores AS (
  SELECT
    co.hadm_id,
    co.cohort_group,
    co.admittime,
    co.dischtime,
    co.hospital_expire_flag,
    COUNT(le.labevent_id) AS instability_score
  FROM
    all_cohorts AS co
  LEFT JOIN
    `physionet-data.mimiciv_3_1_hosp.labevents` AS le
    ON co.hadm_id = le.hadm_id
    AND le.flag = 'abnormal'
    AND le.charttime BETWEEN co.admittime AND TIMESTAMP_ADD(co.admittime, INTERVAL 72 HOUR)
  GROUP BY
    co.hadm_id,
    co.cohort_group,
    co.admittime,
    co.dischtime,
    co.hospital_expire_flag
),

-- Step 5: Calculate the 75th percentile of the instability score for the AMI cohort.
ami_75th_percentile AS (
  SELECT
    APPROX_QUANTILES(instability_score, 100)[OFFSET(75)] AS p75_instability_score
  FROM
    lab_instability_scores
  WHERE
    cohort_group = 'AMI (Male, 44-54)'
),

-- Step 6: Calculate summary statistics (patient count, avg lab freq, avg LOS, mortality) for each cohort.
cohort_summary AS (
  SELECT
    lis.cohort_group,
    COUNT(DISTINCT lis.hadm_id) AS num_admissions,
    AVG(lis.instability_score) AS avg_critical_lab_count_72h,
    AVG(TIMESTAMP_DIFF(lis.dischtime, lis.admittime, HOUR) / 24.0) AS avg_los_days,
    AVG(CAST(lis.hospital_expire_flag AS FLOAT64)) AS mortality_rate
  FROM
    lab_instability_scores AS lis
  GROUP BY
    lis.cohort_group
)

-- Final Step: Combine the 75th percentile result with the cohort comparison table.
SELECT
  p75.p75_instability_score AS p75_ami_lab_instability_score,
  cs.cohort_group,
  cs.num_admissions,
  cs.avg_critical_lab_count_72h,
  cs.avg_los_days,
  cs.mortality_rate
FROM
  cohort_summary AS cs
CROSS JOIN
  ami_75th_percentile AS p75
ORDER BY
  -- Show the AMI cohort first for easy comparison
  CASE WHEN cs.cohort_group = 'AMI (Male, 44-54)' THEN 1 ELSE 2 END;