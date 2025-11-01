WITH pneumonia_icd AS (
  SELECT icd_code, icd_version
  FROM `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses`
  WHERE REGEXP_CONTAINS(LOWER(long_title), r'pneumonia')
),
base_cohort AS (
  SELECT DISTINCT
    p.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    a.hospital_expire_flag,
    p.dod,
    p.anchor_age + (EXTRACT(YEAR FROM a.admittime) - p.anchor_year) AS age
  FROM `physionet-data.mimiciv_3_1_hosp.patients` p
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a
    ON p.subject_id = a.subject_id
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` diag
    ON a.hadm_id = diag.hadm_id
  INNER JOIN pneumonia_icd
    ON diag.icd_code = pneumonia_icd.icd_code
    AND diag.icd_version = pneumonia_icd.icd_version
  WHERE
    p.gender = 'M'
    AND (p.anchor_age + (EXTRACT(YEAR FROM a.admittime) - p.anchor_year)) BETWEEN 73 AND 83
),
comorbidity AS (
  SELECT
    hadm_id,
    COUNT(DISTINCT icd_code) AS comorbidity_count
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd`
  GROUP BY hadm_id
),
cohort_with_cc AS (
  SELECT
    bc.*,
    COALESCE(c.comorbidity_count, 0) AS comorbidity_count
  FROM base_cohort bc
  LEFT JOIN comorbidity c
    ON bc.hadm_id = c.hadm_id
),
cohort_percentiles AS (
  SELECT
    *,
    PERCENT_RANK() OVER (ORDER BY comorbidity_count) * 100 AS comorbidity_percentile
  FROM cohort_with_cc
),
comorbidity_threshold AS (
  SELECT
    APPROX_QUANTILES(comorbidity_count, 100)[OFFSET(75)] AS p75
  FROM cohort_with_cc
),
top_quartile_cohort AS (
  SELECT
    cp.*
  FROM cohort_percentiles cp
  CROSS JOIN comorbidity_threshold
  WHERE comorbidity_count >= p75
),
cohort_icu_flag AS (
  SELECT
    t.hadm_id,
    MAX(CASE WHEN i.hadm_id IS NOT NULL THEN 1 ELSE 0 END) AS had_icu_stay
  FROM top_quartile_cohort t
  LEFT JOIN `physionet-data.mimiciv_3_1_icu.icustays` i
    ON t.hadm_id = i.hadm_id
  GROUP BY t.hadm_id
),
cohort_survival AS (
  SELECT
    hadm_id,
    DATE_DIFF(dod, admittime, DAY) AS survival_days
  FROM top_quartile_cohort
  WHERE dod IS NOT NULL
)
SELECT
  APPROX_QUANTILES(comorbidity_percentile, 100)[OFFSET(50)] AS composite_risk_percentile,
  ROUND(AVG(hospital_expire_flag) * 100, 2) AS in_hospital_mortality_percent,
  ROUND(AVG(had_icu_stay) * 100, 2) AS major_complication_percent,
  APPROX_QUANTILES(survival_days, 100)[OFFSET(50)] AS median_survival_days
FROM top_quartile_cohort t
INNER JOIN cohort_icu_flag icu
  ON t.hadm_id = icu.hadm_id
LEFT JOIN cohort_survival s
  ON t.hadm_id = s.hadm_id;