WITH
-- Step 1: Create a base cohort of female patients aged 68-78 at admission
base_patients_admissions AS (
  SELECT
    p.subject_id,
    p.dod,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    a.hospital_expire_flag,
    -- Calculate age at the time of admission
    (EXTRACT(YEAR FROM a.admittime) - p.anchor_year) + p.anchor_age AS age_at_admission
  FROM
    `physionet-data.mimiciv_3_1_hosp.patients` AS p
  INNER JOIN
    `physionet-data.mimiciv_3_1_hosp.admissions` AS a ON p.subject_id = a.subject_id
  WHERE
    p.gender = 'F'
    AND (EXTRACT(YEAR FROM a.admittime) - p.anchor_year) + p.anchor_age BETWEEN 68 AND 78
),

-- Step 2: Identify admissions from the base cohort that had an AMI diagnosis and an ICU stay
ami_icu_hadms AS (
  SELECT DISTINCT
    bpa.hadm_id
  FROM
    base_patients_admissions AS bpa
  INNER JOIN
    `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` AS dx ON bpa.hadm_id = dx.hadm_id
  INNER JOIN
    `physionet-data.mimiciv_3_1_icu.icustays` AS icu ON bpa.hadm_id = icu.hadm_id
  WHERE
    -- Acute Myocardial Infarction codes for ICD-9 and ICD-10
    (dx.icd_code LIKE '410%' AND dx.icd_version = 9)
    OR (dx.icd_code LIKE 'I21%' AND dx.icd_version = 10)
),

-- Step 3: Identify admissions with a major complication (not primary diagnosis)
complication_hadms AS (
  SELECT DISTINCT
    hadm_id
  FROM
    `physionet-data.mimiciv_3_1_hosp.diagnoses_icd`
  WHERE
    seq_num > 1 AND (
      -- Acute Kidney Failure
      (icd_code LIKE '584%' AND icd_version = 9) OR (icd_code LIKE 'N17%' AND icd_version = 10)
      -- Sepsis/Septic Shock
      OR (icd_code IN ('99591', '99592', '78552') AND icd_version = 9) OR (icd_code LIKE 'A41%' AND icd_version = 10)
      -- Respiratory Failure
      OR (icd_code IN ('51881', '51882', '51884') AND icd_version = 9) OR (icd_code LIKE 'J96%' AND icd_version = 10)
    )
),

-- Step 4: Get the max DRG severity as a proxy for a "risk score" for each admission
risk_scores AS (
  SELECT
    hadm_id,
    MAX(drg_severity) AS risk_score
  FROM
    `physionet-data.mimiciv_3_1_hosp.drgcodes`
  WHERE drg_severity IS NOT NULL
  GROUP BY
    hadm_id
),

-- Step 5: Combine all data, assign cohorts, and create flags for metrics
cohort_data_prepared AS (
  SELECT
    bpa.hadm_id,
    bpa.age_at_admission,
    CASE WHEN aih.hadm_id IS NOT NULL THEN 'AMI_ICU' ELSE 'General' END AS cohort,
    rs.risk_score,
    CASE WHEN ch.hadm_id IS NOT NULL THEN 1 ELSE 0 END AS has_complication,
    DATETIME_DIFF(bpa.dischtime, bpa.admittime, DAY) AS los_days,
    bpa.hospital_expire_flag,
    CASE WHEN bpa.dod IS NOT NULL AND DATE_DIFF(DATE(bpa.dod), DATE(bpa.admittime), DAY) BETWEEN 0 AND 90 THEN 1 ELSE 0 END AS is_90_day_mortality
  FROM
    base_patients_admissions AS bpa
  LEFT JOIN
    ami_icu_hadms AS aih ON bpa.hadm_id = aih.hadm_id
  LEFT JOIN
    complication_hadms AS ch ON bpa.hadm_id = ch.hadm_id
  LEFT JOIN
    risk_scores AS rs ON bpa.hadm_id = rs.hadm_id
),

-- Step 6: Calculate risk percentiles for patients within the AMI cohort
ami_risk_percentiles AS (
  SELECT
    age_at_admission,
    PERCENT_RANK() OVER (ORDER BY risk_score ASC) as risk_percentile
  FROM
    cohort_data_prepared
  WHERE
    cohort = 'AMI_ICU' AND risk_score IS NOT NULL
)

-- Step 7: Aggregate and format all results into a single output table
-- Metric 1: Median Risk Score for AMI Cohort
SELECT
  'Median Risk Score (DRG Severity)' AS metric,
  CAST(risk_quantiles[OFFSET(2)] AS STRING) AS value,
  'AMI_ICU_Cohort' AS cohort
FROM (
  SELECT APPROX_QUANTILES(risk_score, 4) as risk_quantiles
  FROM cohort_data_prepared
  WHERE cohort = 'AMI_ICU' AND risk_score IS NOT NULL
)

UNION ALL

-- Metric 2: IQR Risk Score for AMI Cohort
SELECT
  'IQR Risk Score (DRG Severity)' AS metric,
  CAST(risk_quantiles[OFFSET(3)] - risk_quantiles[OFFSET(1)] AS STRING) AS value,
  'AMI_ICU_Cohort' AS cohort
FROM (
  SELECT APPROX_QUANTILES(risk_score, 4) as risk_quantiles
  FROM cohort_data_prepared
  WHERE cohort = 'AMI_ICU' AND risk_score IS NOT NULL
)

UNION ALL

-- Metric 3: 90-Day Mortality for AMI Cohort
SELECT
  '90-Day Mortality Rate' AS metric,
  CAST(ROUND(AVG(is_90_day_mortality) * 100, 2) AS STRING) || '%' AS value,
  'AMI_ICU_Cohort' AS cohort
FROM
  cohort_data_prepared
WHERE
  cohort = 'AMI_ICU'

UNION ALL

-- Metric 4: Major Complication Rate for both cohorts
SELECT
  'Major Complication Rate' AS metric,
  CAST(ROUND(AVG(has_complication) * 100, 2) AS STRING) || '%' AS value,
  cohort || '_Cohort' AS cohort
FROM
  cohort_data_prepared
GROUP BY
  cohort

UNION ALL

-- Metric 5: Survivor LOS for both cohorts
SELECT
  'Survivor LOS (days)' AS metric,
  CAST(ROUND(AVG(los_days), 1) AS STRING) AS value,
  cohort || '_Cohort' AS cohort
FROM
  cohort_data_prepared
WHERE
  hospital_expire_flag = 0
GROUP BY
  cohort

UNION ALL

-- Metric 6: Risk Percentile for the 73-year-old patient demographic
SELECT
  'Average Risk Percentile for 73 y/o' AS metric,
  CAST(ROUND(AVG(risk_percentile) * 100, 1) AS STRING) || 'th percentile' AS value,
  'AMI_ICU_Cohort' AS cohort
FROM
  ami_risk_percentiles
WHERE
  age_at_admission = 73;