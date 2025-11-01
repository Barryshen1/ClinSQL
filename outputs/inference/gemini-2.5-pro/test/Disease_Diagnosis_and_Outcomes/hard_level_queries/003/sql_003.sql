WITH
-- Step 1: Identify all female inpatients aged 70-80 at the time of admission.
age_cohort AS (
  SELECT
    pat.subject_id,
    adm.hadm_id,
    adm.admittime,
    adm.dischtime,
    pat.dod,
    adm.hospital_expire_flag
  FROM
    `physionet-data.mimiciv_3_1_hosp.patients` AS pat
  INNER JOIN
    `physionet-data.mimiciv_3_1_hosp.admissions` AS adm
    ON pat.subject_id = adm.subject_id
  WHERE
    pat.gender = 'F'
    -- Calculate age at admission to accurately filter the cohort
    AND DATETIME_DIFF(adm.admittime, DATETIME(pat.anchor_year, 1, 1, 0, 0, 0), YEAR) + pat.anchor_age BETWEEN 70 AND 80
),

-- Step 2: For each admission, flag key diagnoses and calculate a risk score.
diagnoses_by_hadm AS (
  SELECT
    hadm_id,
    -- Flag for Pulmonary Embolism (PE) using ICD-9 and ICD-10 codes
    MAX(CASE WHEN icd_code LIKE 'I26%' OR icd_code LIKE '4151%' THEN 1 ELSE 0 END) AS is_pe,
    -- Flag for Acute Kidney Injury (AKI)
    MAX(CASE WHEN icd_code LIKE 'N17%' OR icd_code LIKE '584%' THEN 1 ELSE 0 END) AS has_aki,
    -- Flag for Acute Respiratory Distress Syndrome (ARDS)
    MAX(CASE WHEN icd_code = 'J80' OR icd_code = '51882' THEN 1 ELSE 0 END) AS has_ards,
    -- Define risk score as the count of unique diagnoses for the admission
    COUNT(DISTINCT icd_code) AS risk_score
  FROM
    `physionet-data.mimiciv_3_1_hosp.diagnoses_icd`
  GROUP BY
    hadm_id
),

-- Step 3: Combine age cohort with diagnosis features. This forms the base for both the PE group and the comparison group.
full_cohort_features AS (
  SELECT
    ac.subject_id,
    ac.hadm_id,
    ac.admittime,
    ac.dischtime,
    ac.dod,
    ac.hospital_expire_flag,
    diag.is_pe,
    diag.has_aki,
    diag.has_ards,
    diag.risk_score
  FROM
    age_cohort AS ac
  INNER JOIN
    diagnoses_by_hadm AS diag
    ON ac.hadm_id = diag.hadm_id
),

-- Step 4: Calculate the comparison 90-day mortality for the general 70-80 female inpatient population.
comparison_mortality AS (
  SELECT
    AVG(CASE WHEN dod IS NOT NULL AND DATETIME_DIFF(dod, admittime, DAY) <= 90 THEN 1.0 ELSE 0.0 END) AS general_90d_mortality
  FROM
    full_cohort_features
),

-- Step 5: Filter for the PE cohort, calculate derived metrics, and assign risk quintiles.
pe_cohort_quintiles AS (
  SELECT
    hadm_id,
    hospital_expire_flag,
    has_aki,
    has_ards,
    (dod IS NOT NULL AND DATETIME_DIFF(dod, admittime, DAY) <= 90) AS died_within_90_days,
    DATETIME_DIFF(dischtime, admittime, DAY) AS los_days,
    NTILE(5) OVER (ORDER BY risk_score) AS risk_quintile
  FROM
    full_cohort_features
  WHERE
    is_pe = 1
)

-- Step 6: Final aggregation to report metrics per quintile.
SELECT
  pq.risk_quintile,
  COUNT(pq.hadm_id) AS num_patients,
  -- FIX: Use a CASE statement to convert the boolean `died_within_90_days` to a number (1.0/0.0) for averaging.
  AVG(CASE WHEN pq.died_within_90_days THEN 1.0 ELSE 0.0 END) AS quintile_90d_mortality,
  cm.general_90d_mortality,
  -- REFINEMENT: Remove redundant CAST as `has_aki` and `has_ards` are already 0/1 integers.
  AVG(pq.has_aki) AS aki_rate,
  AVG(pq.has_ards) AS ards_rate,
  APPROX_QUANTILES(
    IF(pq.hospital_expire_flag = 0, pq.los_days, NULL), 100
  )[OFFSET(50)] AS median_survivor_los_days
FROM
  pe_cohort_quintiles AS pq,
  comparison_mortality AS cm -- Cross-join to add the single comparison value to each row
GROUP BY
  pq.risk_quintile,
  cm.general_90d_mortality
ORDER BY
  pq.risk_quintile;