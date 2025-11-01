WITH
-- Step 1: Identify all female admissions with an admission age between 59 and 69.
female_admissions_in_age_range AS (
  SELECT
    p.subject_id,
    a.hadm_id,
    a.admittime,
    a.deathtime,
    a.hospital_expire_flag
  FROM
    `physionet-data.mimiciv_3_1_hosp.patients` AS p
  INNER JOIN
    `physionet-data.mimiciv_3_1_hosp.admissions` AS a
    ON p.subject_id = a.subject_id
  WHERE
    p.gender = 'F'
    -- Calculate age at the time of admission and filter.
    AND ((EXTRACT(YEAR FROM a.admittime) - p.anchor_year) + p.anchor_age) BETWEEN 59 AND 69
),

-- Step 2: From the above group, select only admissions with a Heart Failure (HF) diagnosis.
hf_cohort AS (
  SELECT DISTINCT
    fa.subject_id,
    fa.hadm_id,
    fa.admittime,
    fa.deathtime,
    fa.hospital_expire_flag
  FROM
    female_admissions_in_age_range AS fa
  INNER JOIN
    `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` AS dx
    ON fa.hadm_id = dx.hadm_id
  INNER JOIN
    `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` AS d_dx
    ON dx.icd_code = d_dx.icd_code AND dx.icd_version = d_dx.icd_version
  WHERE
    LOWER(d_dx.long_title) LIKE '%heart failure%'
),

-- Step 3: For all hospital admissions, create flags for AKI and ARDS diagnoses.
-- This is calculated across all admissions for efficiency and then joined to our cohort.
outcome_diagnoses AS (
  SELECT
    dx.hadm_id,
    -- Flag for Acute Kidney Injury
    MAX(
      CASE
        WHEN
          LOWER(d_dx.long_title) LIKE '%acute kidney failure%'
          OR LOWER(d_dx.long_title) LIKE '%acute kidney injury%'
          OR LOWER(d_dx.long_title) LIKE '%acute renal failure%'
          THEN 1
        ELSE 0
      END
    ) AS has_aki,
    -- Flag for Acute Respiratory Distress Syndrome
    MAX(
      CASE
        WHEN LOWER(d_dx.long_title) LIKE '%acute respiratory distress syndrome%'
          THEN 1
        ELSE 0
      END
    ) AS has_ards
  FROM
    `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` AS dx
  INNER JOIN
    `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` AS d_dx
    ON dx.icd_code = d_dx.icd_code AND dx.icd_version = d_dx.icd_version
  GROUP BY
    dx.hadm_id
),

-- Step 4: Combine the HF cohort with outcome flags and calculate per-patient metrics.
final_cohort_data AS (
  SELECT
    hfc.hadm_id,
    hfc.hospital_expire_flag,
    COALESCE(od.has_aki, 0) AS has_aki,
    COALESCE(od.has_ards, 0) AS has_ards,
    -- Calculate survival days ONLY for patients who died in-hospital.
    CASE
      WHEN hfc.hospital_expire_flag = 1
        THEN DATETIME_DIFF(hfc.deathtime, hfc.admittime, DAY)
      ELSE NULL
    END AS survival_days_if_died,
    -- Calculate composite risk score (0 to 3) by summing the outcome flags.
    (
      hfc.hospital_expire_flag + COALESCE(od.has_aki, 0)
      + COALESCE(od.has_ards, 0)
    ) AS composite_risk_score
  FROM
    hf_cohort AS hfc
  LEFT JOIN -- Use LEFT JOIN to ensure we don't lose patients from the HF cohort.
    outcome_diagnoses AS od
    ON hfc.hadm_id = od.hadm_id
),

-- Step 5: Perform the main aggregations once for efficiency.
aggregated_metrics AS (
  SELECT
    AVG(hospital_expire_flag) AS avg_mortality,
    AVG(has_aki) AS avg_aki,
    AVG(has_ards) AS avg_ards,
    APPROX_QUANTILES(survival_days_if_died, 2) AS median_survival_quantiles,
    APPROX_QUANTILES(composite_risk_score, 100) AS risk_score_quantiles
  FROM final_cohort_data
)

-- Step 6: Format and present the final results.
SELECT
  -- Rates
  ROUND(agg.avg_mortality * 100, 2) AS in_hospital_mortality_rate,
  ROUND(agg.avg_aki * 100, 2) AS aki_rate,
  ROUND(agg.avg_ards * 100, 2) AS ards_rate,

  -- Median Survival
  agg.median_survival_quantiles[OFFSET(1)] AS median_survival_days_among_deaths,

  -- Composite Risk Score Distribution
  agg.risk_score_quantiles[OFFSET(0)] AS composite_risk_score_min,
  agg.risk_score_quantiles[OFFSET(25)] AS composite_risk_score_p25,
  agg.risk_score_quantiles[OFFSET(50)] AS composite_risk_score_median,
  agg.risk_score_quantiles[OFFSET(75)] AS composite_risk_score_p75,
  agg.risk_score_quantiles[OFFSET(90)] AS composite_risk_score_p90,
  agg.risk_score_quantiles[OFFSET(100)] AS composite_risk_score_max
FROM
  aggregated_metrics AS agg;