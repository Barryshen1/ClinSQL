WITH base_cohort AS (
  SELECT
    a.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    p.gender,
    -- Calculate age at admission
    p.anchor_age + (EXTRACT(YEAR FROM a.admittime) - p.anchor_year) AS age_at_admission,
    -- 30-day mortality flag
    CASE WHEN p.dod IS NOT NULL AND DATETIME_DIFF(CAST(p.dod AS DATETIME), a.admittime, DAY) <= 30 THEN 1 ELSE 0 END AS mortality_30d,
    -- Hospital LOS in days
    DATETIME_DIFF(a.dischtime, a.admittime, HOUR) / 24.0 AS hospital_los
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON a.subject_id = p.subject_id
  WHERE p.gender = 'M'
    AND p.anchor_age + (EXTRACT(YEAR FROM a.admittime) - p.anchor_year) BETWEEN 74 AND 84
),

icu_cohort AS (
  SELECT
    b.*
  FROM base_cohort b
  INNER JOIN `physionet-data.mimiciv_3_1_icu.icustays` i
    ON b.hadm_id = i.hadm_id
),

aki_cohort AS (
  SELECT
    i.*,
    MAX(CASE WHEN d.icd_version = 10 AND d.icd_code LIKE 'N17%' THEN 1 ELSE 0 END) AS has_aki
  FROM icu_cohort i
  LEFT JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
    ON i.hadm_id = d.hadm_id
  GROUP BY i.subject_id, i.hadm_id, i.admittime, i.dischtime, i.gender, i.age_at_admission, i.mortality_30d, i.hospital_los
),

ards_cohort AS (
  SELECT
    a.*,
    MAX(CASE WHEN d.icd_version = 10 AND d.icd_code = 'J80' THEN 1 ELSE 0 END) AS has_ards
  FROM aki_cohort a
  LEFT JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
    ON a.hadm_id = d.hadm_id
  GROUP BY a.subject_id, a.hadm_id, a.admittime, a.dischtime, a.gender, a.age_at_admission, a.mortality_30d, a.hospital_los, a.has_aki
),

-- Simplified SOFA score calculation
sofa_cohort AS (
  SELECT
    c.*,
    -- Placeholder for SOFA score
    c.age_at_admission / 10 AS sofa_score
  FROM ards_cohort c
),

aki_stats AS (
  SELECT
    -- AKI cohort statistics
    APPROX_QUANTILES(sofa_score, 100)[OFFSET(50)] AS akicohort_median_risk,
    APPROX_QUANTILES(sofa_score, 100)[OFFSET(25)] AS akicohort_iqr_risk_lower,
    APPROX_QUANTILES(sofa_score, 100)[OFFSET(75)] AS akicohort_iqr_risk_upper,
    AVG(mortality_30d) AS akicohort_mortality_30d,
    AVG(has_ards) AS akicohort_ards_rate,
    APPROX_QUANTILES(CASE WHEN mortality_30d = 0 THEN hospital_los END, 100)[OFFSET(50)] AS akicohort_median_survivor_los,
    APPROX_QUANTILES(CASE WHEN mortality_30d = 0 THEN hospital_los END, 100)[OFFSET(25)] AS akicohort_iqr_survivor_los_lower,
    APPROX_QUANTILES(CASE WHEN mortality_30d = 0 THEN hospital_los END, 100)[OFFSET(75)] AS akicohort_iqr_survivor_los_upper
  FROM sofa_cohort
  WHERE has_aki = 1
),

general_stats AS (
  SELECT
    -- General cohort statistics
    AVG(has_ards) AS general_ards_rate,
    APPROX_QUANTILES(CASE WHEN mortality_30d = 0 THEN hospital_los END, 100)[OFFSET(50)] AS general_median_survivor_los,
    APPROX_QUANTILES(CASE WHEN mortality_30d = 0 THEN hospital_los END, 100)[OFFSET(25)] AS general_iqr_survivor_los_lower,
    APPROX_QUANTILES(CASE WHEN mortality_30d = 0 THEN hospital_los END, 100)[OFFSET(75)] AS general_iqr_survivor_los_upper,
    APPROX_QUANTILES(sofa_score, 100) AS general_sofa_quantiles
  FROM sofa_cohort
),

aki_median AS (
  SELECT
    APPROX_QUANTILES(sofa_score, 100)[OFFSET(50)] AS akicohort_median_risk
  FROM sofa_cohort
  WHERE has_aki = 1
),

risk_percentile AS (
  SELECT
    SUM(CASE WHEN sofa_score <= (SELECT akicohort_median_risk FROM aki_median) THEN 1 ELSE 0 END) * 100.0 / 
    COUNT(*) AS risk_percentile
  FROM sofa_cohort
)

SELECT
  (SELECT akicohort_median_risk FROM aki_stats) AS akicohort_median_risk,
  (SELECT akicohort_iqr_risk_lower FROM aki_stats) AS akicohort_iqr_risk_lower,
  (SELECT akicohort_iqr_risk_upper FROM aki_stats) AS akicohort_iqr_risk_upper,
  (SELECT akicohort_mortality_30d FROM aki_stats) AS akicohort_mortality_30d,
  (SELECT akicohort_ards_rate FROM aki_stats) AS akicohort_ards_rate,
  (SELECT akicohort_median_survivor_los FROM aki_stats) AS akicohort_median_survivor_los,
  (SELECT akicohort_iqr_survivor_los_lower FROM aki_stats) AS akicohort_iqr_survivor_los_lower,
  (SELECT akicohort_iqr_survivor_los_upper FROM aki_stats) AS akicohort_iqr_survivor_los_upper,
  (SELECT general_ards_rate FROM general_stats) AS general_ards_rate,
  (SELECT general_median_survivor_los FROM general_stats) AS general_median_survivor_los,
  (SELECT general_iqr_survivor_los_lower FROM general_stats) AS general_iqr_survivor_los_lower,
  (SELECT general_iqr_survivor_los_upper FROM general_stats) AS general_iqr_survivor_los_upper,
  (SELECT risk_percentile FROM risk_percentile) AS risk_percentile;