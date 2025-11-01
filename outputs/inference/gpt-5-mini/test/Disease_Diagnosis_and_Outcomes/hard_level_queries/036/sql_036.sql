WITH
pneumonia_admissions AS (
  SELECT DISTINCT di.hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` di
  JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` d
    ON di.icd_code = d.icd_code
  WHERE LOWER(COALESCE(d.long_title, '')) LIKE '%pneumonia%'
),

-- base cohort: male, age 73-83 inclusive, with pneumonia admission
base_cohort AS (
  SELECT
    a.subject_id,
    a.hadm_id,
    p.anchor_age,
    p.gender,
    a.admittime,
    a.dischtime,
    a.deathtime,
    a.hospital_expire_flag
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON a.subject_id = p.subject_id
  JOIN pneumonia_admissions pa
    ON a.hadm_id = pa.hadm_id
  WHERE p.gender = 'M'
    AND p.anchor_age BETWEEN 73 AND 83
),

-- comorbidity proxy: number of distinct diagnosis codes on the admission
comorbidity_counts AS (
  SELECT
    di.hadm_id,
    COUNT(DISTINCT di.icd_code) AS comorbidity_count
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` di
  GROUP BY di.hadm_id
),

-- attach comorbidity counts to base cohort
cohort_with_comorb AS (
  SELECT
    bc.*,
    COALESCE(cc.comorbidity_count, 0) AS comorbidity_count
  FROM base_cohort bc
  LEFT JOIN comorbidity_counts cc
    ON bc.hadm_id = cc.hadm_id
),

-- compute the 75th percentile of the comorbidity_count within the base cohort
comorbidity_threshold AS (
  SELECT
    APPROX_QUANTILES(comorbidity_count, 100)[OFFSET(75)] AS p75_comorb_count
  FROM cohort_with_comorb
),

-- flag top-quartile admissions and identify major complications; compute survival_days for in-hospital deaths
cohort_flagged AS (
  SELECT
    cwc.*,
    CASE WHEN cwc.comorbidity_count >= COALESCE(ct.p75_comorb_count, 0) THEN 1 ELSE 0 END AS top_quartile_comorbidity,
    -- major complication: any diagnosis on the same hadm_id with long_title matching key severe outcomes
    CASE
      WHEN EXISTS (
        SELECT 1
        FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` di
        JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` d
          ON di.icd_code = d.icd_code
        WHERE di.hadm_id = cwc.hadm_id
          AND REGEXP_CONTAINS(LOWER(COALESCE(d.long_title, '')),
            '(sepsis|septic|respiratory failure|acute respiratory failure|shock|cardiac arrest|myocardial infarction|acute myocardial|acute renal failure|acute kidney)')
      ) THEN 1 ELSE 0
    END AS major_complication_flag,
    CASE WHEN cwc.hospital_expire_flag = 1 AND cwc.deathtime IS NOT NULL THEN
      TIMESTAMP_DIFF(cwc.deathtime, cwc.admittime, DAY)
    ELSE NULL END AS survival_days
  FROM cohort_with_comorb cwc
  CROSS JOIN comorbidity_threshold ct  -- to get p75 threshold
),

-- compute composite score per admission in base cohort: weight mortality 0.6, major complication 0.4
base_scores AS (
  SELECT
    hadm_id,
    subject_id,
    anchor_age,
    gender,
    comorbidity_count,
    top_quartile_comorbidity,
    major_complication_flag,
    hospital_expire_flag,
    survival_days,
    (0.6 * SAFE_CAST(hospital_expire_flag AS FLOAT64) + 0.4 * SAFE_CAST(major_complication_flag AS FLOAT64)) AS composite_score
  FROM cohort_flagged
),

-- compute the median composite score among top-quartile-comorbidity subgroup
top_quartile_median AS (
  SELECT
    APPROX_QUANTILES(composite_score, 100)[OFFSET(50)] AS median_composite_score
  FROM base_scores
  WHERE top_quartile_comorbidity = 1
),

-- median survival days among in-hospital deaths in the top-quartile subgroup
top_quartile_median_survival AS (
  SELECT
    APPROX_QUANTILES(survival_days, 100)[OFFSET(50)] AS median_survival_days
  FROM base_scores
  WHERE top_quartile_comorbidity = 1
    AND survival_days IS NOT NULL
),

-- aggregate metrics for the top-quartile subgroup and compute percentile of the subgroup median composite in base cohort
final_metrics AS (
  SELECT
    COUNTIF(top_quartile_comorbidity = 1) AS top_quartile_cohort_size,
    100.0 * SAFE_DIVIDE(SUM(CASE WHEN top_quartile_comorbidity = 1 THEN SAFE_CAST(hospital_expire_flag AS FLOAT64) ELSE 0 END), NULLIF(COUNTIF(top_quartile_comorbidity = 1),0)) AS top_quartile_mortality_pct,
    100.0 * SAFE_DIVIDE(SUM(CASE WHEN top_quartile_comorbidity = 1 THEN SAFE_CAST(major_complication_flag AS FLOAT64) ELSE 0 END), NULLIF(COUNTIF(top_quartile_comorbidity = 1),0)) AS top_quartile_major_complication_pct,
    (SELECT median_survival_days FROM top_quartile_median_survival) AS top_quartile_median_survival_days,
    (SELECT median_composite_score FROM top_quartile_median) AS top_quartile_median_composite_score,
    100.0 * SAFE_DIVIDE(
      SUM(CASE WHEN composite_score <= (SELECT median_composite_score FROM top_quartile_median) THEN 1 ELSE 0 END),
      COUNT(*)
    ) AS percentile_of_top_quartile_median_in_base_pct
  FROM base_scores
)

SELECT
  top_quartile_cohort_size,
  ROUND(top_quartile_mortality_pct, 2) AS top_quartile_mortality_percent,
  ROUND(top_quartile_major_complication_pct, 2) AS top_quartile_major_complication_percent,
  top_quartile_median_survival_days,
  ROUND(top_quartile_median_composite_score, 3) AS top_quartile_median_composite_score,
  ROUND(percentile_of_top_quartile_median_in_base_pct, 1) AS his_composite_risk_percentile_among_base_cohort
FROM final_metrics;