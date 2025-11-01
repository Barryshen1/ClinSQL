WITH ami_icd_codes AS (
  -- AMI ICD-9: 410.x; ICD-10: I21.x, I22.x
  SELECT icd_code, icd_version
  FROM `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses`
  WHERE 
    (icd_version = 9 AND REGEXP_CONTAINS(icd_code, r'^410')) OR
    (icd_version = 10 AND (REGEXP_CONTAINS(icd_code, r'^I21') OR REGEXP_CONTAINS(icd_code, r'^I22')))
),
aki_icd_codes AS (
  -- AKI ICD-9: 584.x; ICD-10: N17.x
  SELECT icd_code, icd_version
  FROM `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses`
  WHERE 
    (icd_version = 9 AND REGEXP_CONTAINS(icd_code, r'^584')) OR
    (icd_version = 10 AND REGEXP_CONTAINS(icd_code, r'^N17'))
),
ards_icd_codes AS (
  -- ARDS ICD-9: 518.82; ICD-10: J80
  SELECT icd_code, icd_version
  FROM `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses`
  WHERE 
    (icd_version = 9 AND icd_code = '51882') OR
    (icd_version = 10 AND icd_code = 'J80')
),
cohort AS (
  SELECT
    p.subject_id,
    a.hadm_id,
    p.gender,
    p.anchor_age,
    a.admittime,
    a.dischtime,
    p.dod,
    icu.stay_id,
    icu.intime AS icu_intime,
    icu.outtime AS icu_outtime
  FROM `physionet-data.mimiciv_3_1_hosp.patients` p
  JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a
    ON p.subject_id = a.subject_id
  JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
    ON a.hadm_id = d.hadm_id
  JOIN ami_icd_codes ami
    ON d.icd_code = ami.icd_code AND d.icd_version = ami.icd_version
  JOIN `physionet-data.mimiciv_3_1_icu.icustays` icu
    ON a.hadm_id = icu.hadm_id
  WHERE
    p.gender = 'F'
    AND p.anchor_age BETWEEN 88 AND 98
),
cohort_with_outcomes AS (
  SELECT
    c.*,
    -- 30-day mortality: death within 30 days of ICU discharge
    CASE
      WHEN c.dod IS NOT NULL AND DATETIME(c.dod) <= DATETIME(c.icu_outtime) + INTERVAL 30 DAY THEN 1
      ELSE 0
    END AS mortality_30d,
    -- Survival time (days) for decedents
    CASE
      WHEN c.dod IS NOT NULL THEN DATE_DIFF(DATE(c.dod), DATE(c.icu_outtime), DAY)
      ELSE NULL
    END AS survival_days
  FROM cohort c
),
aki_flags AS (
  SELECT DISTINCT hadm_id, 1 AS has_aki
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
  JOIN aki_icd_codes aki
    ON d.icd_code = aki.icd_code AND d.icd_version = aki.icd_version
),
ards_flags AS (
  SELECT DISTINCT hadm_id, 1 AS has_ards
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
  JOIN ards_icd_codes ards
    ON d.icd_code = ards.icd_code AND d.icd_version = ards.icd_version
),
final_cohort AS (
  SELECT
    c.subject_id,
    c.hadm_id,
    c.gender,
    c.anchor_age,
    c.admittime,
    c.dischtime,
    c.dod,
    c.stay_id,
    c.icu_intime,
    c.icu_outtime,
    c.mortality_30d,
    c.survival_days,
    IFNULL(aki.has_aki, 0) AS has_aki,
    IFNULL(ards.has_ards, 0) AS has_ards
    -- Placeholder for composite risk percentile: NULL
  FROM cohort_with_outcomes c
  LEFT JOIN aki_flags aki ON c.hadm_id = aki.hadm_id
  LEFT JOIN ards_flags ards ON c.hadm_id = ards.hadm_id
)
SELECT
  COUNT(*) AS cohort_size,
  -- Composite risk percentile: placeholder (NULL)
  NULL AS avg_composite_risk_percentile,
  ROUND(SUM(mortality_30d) / COUNT(*) * 100, 2) AS mortality_30d_rate_percent,
  ROUND(SUM(has_aki) / COUNT(*) * 100, 2) AS aki_rate_percent,
  ROUND(SUM(has_ards) / COUNT(*) * 100, 2) AS ards_rate_percent,
  APPROX_QUANTILES(survival_days, 2)[OFFSET(1)] AS median_survival_days_decedents
FROM final_cohort
WHERE
  -- Only count survival for decedents
  TRUE
;