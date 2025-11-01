WITH base_cohort AS (
  SELECT DISTINCT
    p.subject_id,
    adm.hadm_id,
    p.anchor_age,
    p.gender,
    adm.hospital_expire_flag,
    adm.admittime,
    adm.dischtime
  FROM `physionet-data.mimiciv_3_1_hosp.patients` p
  JOIN `physionet-data.mimiciv_3_1_hosp.admissions` adm
    ON p.subject_id = adm.subject_id
  JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` dx
    ON adm.hadm_id = dx.hadm_id
  JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` ddx
    ON dx.icd_code = ddx.icd_code
    AND dx.icd_version = ddx.icd_version
  JOIN `physionet-data.mimiciv_3_1_icu.icustays` icu
    ON adm.hadm_id = icu.hadm_id
  WHERE p.gender = 'M'
    AND p.anchor_age BETWEEN 88 AND 98
    AND LOWER(ddx.long_title) LIKE '%pneumonia%'
),
drg_scores AS (
  SELECT hadm_id, MAX(drg_severity) + MAX(drg_mortality) AS composite_score
  FROM `physionet-data.mimiciv_3_1_hosp.drgcodes`
  GROUP BY hadm_id
),
aki_flags AS (
  SELECT DISTINCT hadm_id, 1 AS aki_flag
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd`
  WHERE (icd_version = 9 AND icd_code LIKE '584%')
     OR (icd_version = 10 AND icd_code LIKE 'N17%')
),
ards_flags AS (
  SELECT DISTINCT hadm_id, 1 AS ards_flag
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd`
  WHERE (icd_version = 9 AND (icd_code IN ('51882','51881','5185')))
     OR (icd_version = 10 AND icd_code = 'J80')
),
cohort_with_flags AS (
  SELECT
    b.subject_id,
    b.hadm_id,
    b.hospital_expire_flag,
    b.admittime,
    b.dischtime,
    d.composite_score,
    IFNULL(a.aki_flag,0) AS aki_flag,
    IFNULL(r.ards_flag,0) AS ards_flag
  FROM base_cohort b
  LEFT JOIN drg_scores d USING (hadm_id)
  LEFT JOIN aki_flags a USING (hadm_id)
  LEFT JOIN ards_flags r USING (hadm_id)
),
composite_percentiles AS (
  SELECT
    APPROX_QUANTILES(composite_score, 100)[SAFE_OFFSET(0)] AS composite_min,
    APPROX_QUANTILES(composite_score, 100)[SAFE_OFFSET(25)] AS composite_p25,
    APPROX_QUANTILES(composite_score, 100)[SAFE_OFFSET(50)] AS composite_median,
    APPROX_QUANTILES(composite_score, 100)[SAFE_OFFSET(75)] AS composite_p75,
    APPROX_QUANTILES(composite_score, 100)[SAFE_OFFSET(100)] AS composite_max
  FROM cohort_with_flags
  WHERE composite_score IS NOT NULL
),
median_survival_decedents AS (
  SELECT
    APPROX_QUANTILES(DATE_DIFF(dischtime, admittime, DAY), 100)[SAFE_OFFSET(50)] AS median_survival_days_decedents
  FROM cohort_with_flags
  WHERE hospital_expire_flag = 1
),
cohort_metrics AS (
  SELECT
    COUNT(DISTINCT subject_id) AS cohort_size,
    100.0 * SUM(CASE WHEN hospital_expire_flag = 1 THEN 1 ELSE 0 END) / COUNT(*) AS mortality_rate_percent,
    100.0 * SUM(aki_flag) / COUNT(*) AS aki_rate_percent,
    100.0 * SUM(ards_flag) / COUNT(*) AS ards_rate_percent
  FROM cohort_with_flags
  WHERE composite_score IS NOT NULL
)
SELECT
  cm.cohort_size,
  cp.composite_min,
  cp.composite_p25,
  cp.composite_median,
  cp.composite_p75,
  cp.composite_max,
  cm.mortality_rate_percent,
  cm.aki_rate_percent,
  cm.ards_rate_percent,
  msd.median_survival_days_decedents
FROM cohort_metrics cm
CROSS JOIN composite_percentiles cp
CROSS JOIN median_survival_decedents msd;