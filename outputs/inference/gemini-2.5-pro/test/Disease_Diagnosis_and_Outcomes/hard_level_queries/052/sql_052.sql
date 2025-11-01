WITH
-- Step 1: Create a base cohort of all female inpatients aged 75-85
base_patients AS (
  SELECT
    p.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    p.dod,
    -- Calculate age at admission
    (EXTRACT(YEAR FROM a.admittime) - p.anchor_year + p.anchor_age) AS age_at_admission,
    -- Calculate Length of Stay in days
    DATETIME_DIFF(a.dischtime, a.admittime, DAY) AS los_days,
    -- Flag for 90-day mortality
    CASE
      WHEN p.dod IS NOT NULL AND DATE_DIFF(DATE(p.dod), DATE(a.admittime), DAY) BETWEEN 0 AND 90
      THEN 1
      ELSE 0
    END AS dead_within_90_days
  FROM
    `physionet-data.mimiciv_3_1_hosp.patients` AS p
  INNER JOIN
    `physionet-data.mimiciv_3_1_hosp.admissions` AS a
    ON p.subject_id = a.subject_id
  WHERE
    p.gender = 'F'
    AND (EXTRACT(YEAR FROM a.admittime) - p.anchor_year + p.anchor_age) BETWEEN 75 AND 85
),

-- Step 2: Identify admissions specifically for COPD exacerbation from the base cohort
copd_admissions AS (
  SELECT DISTINCT
    bp.hadm_id
  FROM
    base_patients AS bp
  INNER JOIN
    `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` AS dx
    ON bp.hadm_id = dx.hadm_id
  WHERE
    -- ICD-9 for COPD with acute exacerbation
    (dx.icd_code = '49121' AND dx.icd_version = 9)
    -- ICD-10 for COPD with acute exacerbation
    OR (dx.icd_code = 'J441' AND dx.icd_version = 10)
),

-- Step 3: Define and calculate the composite risk score for the COPD cohort
-- We use the total number of unique diagnoses as a proxy for comorbidity burden.
risk_score AS (
  SELECT
    hadm_id,
    COUNT(DISTINCT icd_code) AS comorbidity_count
  FROM
    `physionet-data.mimiciv_3_1_hosp.diagnoses_icd`
  WHERE
    hadm_id IN (SELECT hadm_id FROM copd_admissions)
  GROUP BY
    hadm_id
),

-- Step 4: Identify hadm_ids with a major complication during their stay
-- Major complication = Sepsis, Acute Respiratory Failure, or Mechanical Ventilation
major_complications AS (
  SELECT DISTINCT hadm_id FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd`
  WHERE
    hadm_id IN (SELECT hadm_id FROM copd_admissions) AND
    (
      -- Sepsis
      (icd_version = 9 AND icd_code IN ('99591', '99592'))
      OR (icd_version = 10 AND (icd_code LIKE 'A40%' OR icd_code LIKE 'A41%'))
      -- Acute Respiratory Failure
      OR (icd_version = 9 AND icd_code IN ('51881', '51884'))
      OR (icd_version = 10 AND (icd_code LIKE 'J960%' OR icd_code LIKE 'J962%'))
    )
  UNION DISTINCT
  SELECT DISTINCT hadm_id FROM `physionet-data.mimiciv_3_1_hosp.procedures_icd`
  WHERE
    hadm_id IN (SELECT hadm_id FROM copd_admissions) AND
    (
      -- Mechanical Ventilation
      (icd_version = 9 AND icd_code IN ('9670', '9671', '9672'))
      OR (icd_version = 10 AND icd_code IN ('5A1935Z', '5A1945Z', '5A1955Z'))
    )
),

-- Step 5: Combine all features for the COPD cohort
-- Join cohort, outcomes, risk score, and complication flags
cohort_features AS (
  SELECT
    bp.hadm_id,
    bp.dead_within_90_days,
    bp.los_days,
    rs.comorbidity_count,
    CASE
      WHEN mc.hadm_id IS NOT NULL THEN 1
      ELSE 0
    END AS had_major_complication
  FROM
    base_patients AS bp
  INNER JOIN
    copd_admissions AS ca ON bp.hadm_id = ca.hadm_id
  INNER JOIN
    risk_score AS rs ON bp.hadm_id = rs.hadm_id
  LEFT JOIN
    major_complications AS mc ON bp.hadm_id = mc.hadm_id
),

-- Step 6: Stratify the COPD cohort into quartiles based on the risk score
cohort_quartiles AS (
  SELECT
    hadm_id,
    dead_within_90_days,
    los_days,
    had_major_complication,
    NTILE(4) OVER (ORDER BY comorbidity_count) AS risk_quartile
  FROM
    cohort_features
),

-- Step 7: Calculate the requested metrics per quartile for the COPD cohort
quartile_metrics AS (
  SELECT
    risk_quartile,
    COUNT(hadm_id) AS n_patients,
    -- 90-day mortality rate per quartile
    AVG(dead_within_90_days) AS ninety_day_mortality_rate,
    -- Major complication rate per quartile
    AVG(had_major_complication) AS major_complication_rate,
    -- Median LOS for survivors only, per quartile
    APPROX_QUANTILES(
      CASE WHEN dead_within_90_days = 0 THEN los_days END, 100
    )[OFFSET(50)] AS median_survivor_los_days
  FROM
    cohort_quartiles
  GROUP BY
    risk_quartile
),

-- Step 8: Calculate the benchmark 90-day mortality for the broader 75-85 female population
benchmark_mortality AS (
  SELECT
    AVG(dead_within_90_days) AS broader_female_75_85_90d_mortality
  FROM
    base_patients
)

-- Final Step: Combine the quartile report with the benchmark value
SELECT
  qm.risk_quartile,
  qm.n_patients,
  qm.ninety_day_mortality_rate,
  qm.major_complication_rate,
  qm.median_survivor_los_days,
  bm.broader_female_75_85_90d_mortality
FROM
  quartile_metrics AS qm
CROSS JOIN
  benchmark_mortality AS bm
ORDER BY
  qm.risk_quartile;