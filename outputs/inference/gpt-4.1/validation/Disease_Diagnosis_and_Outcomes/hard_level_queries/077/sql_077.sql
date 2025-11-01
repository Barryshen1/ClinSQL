WITH pneumonia_admissions AS (
  SELECT
    adm.subject_id,
    adm.hadm_id,
    adm.admittime,
    adm.dischtime,
    adm.deathtime,
    adm.hospital_expire_flag,
    pat.anchor_age,
    pat.gender
  FROM
    `physionet-data.mimiciv_3_1_hosp.admissions` adm
    JOIN `physionet-data.mimiciv_3_1_hosp.patients` pat
      ON adm.subject_id = pat.subject_id
  WHERE
    pat.gender = 'M'
    AND pat.anchor_age BETWEEN 88 AND 98
),
pneumonia_dx AS (
  SELECT
    dx.subject_id,
    dx.hadm_id
  FROM
    `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` dx
    JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` did
      ON dx.icd_code = did.icd_code
      AND dx.icd_version = did.icd_version
  WHERE
    -- ICD-10: J12-J18, ICD-9: 480-486
    (
      (dx.icd_version = 10 AND REGEXP_CONTAINS(dx.icd_code, r'^J1[2-8]'))
      OR
      (dx.icd_version = 9 AND REGEXP_CONTAINS(dx.icd_code, r'^(480|481|482|483|484|485|486)(\.|$)'))
    )
),
aki_dx AS (
  SELECT DISTINCT
    dx.subject_id,
    dx.hadm_id
  FROM
    `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` dx
  WHERE
    -- ICD-10: N17, ICD-9: 584
    (
      (dx.icd_version = 10 AND dx.icd_code = 'N17')
      OR
      (dx.icd_version = 9 AND dx.icd_code = '584')
    )
),
ards_dx AS (
  SELECT DISTINCT
    dx.subject_id,
    dx.hadm_id
  FROM
    `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` dx
  WHERE
    -- ICD-10: J80, ICD-9: 518.82
    (
      (dx.icd_version = 10 AND dx.icd_code = 'J80')
      OR
      (dx.icd_version = 9 AND dx.icd_code = '51882')
    )
),
icu_admissions AS (
  SELECT DISTINCT
    stay.subject_id,
    stay.hadm_id
  FROM
    `physionet-data.mimiciv_3_1_icu.icustays` stay
),
cohort AS (
  SELECT
    pa.subject_id,
    pa.hadm_id,
    pa.admittime,
    pa.dischtime,
    pa.deathtime,
    pa.hospital_expire_flag,
    pa.anchor_age,
    -- Outcomes
    IF(aki.subject_id IS NOT NULL, 1, 0) AS has_aki,
    IF(ards.subject_id IS NOT NULL, 1, 0) AS has_ards
  FROM
    pneumonia_admissions pa
    INNER JOIN pneumonia_dx pdx
      ON pa.subject_id = pdx.subject_id AND pa.hadm_id = pdx.hadm_id
    INNER JOIN icu_admissions icu
      ON pa.subject_id = icu.subject_id AND pa.hadm_id = icu.hadm_id
    LEFT JOIN aki_dx aki
      ON pa.subject_id = aki.subject_id AND pa.hadm_id = aki.hadm_id
    LEFT JOIN ards_dx ards
      ON pa.subject_id = ards.subject_id AND pa.hadm_id = ards.hadm_id
)
, risk_scores AS (
  SELECT
    *,
    -- Composite risk score: age + 10*death + 5*AKI + 5*ARDS
    anchor_age + 10 * hospital_expire_flag + 5 * has_aki + 5 * has_ards AS composite_risk_score,
    -- Survival days for decedents
    CASE
      WHEN hospital_expire_flag = 1 AND deathtime IS NOT NULL AND admittime IS NOT NULL
        THEN DATE_DIFF(DATE(deathtime), DATE(admittime), DAY)
      ELSE NULL
    END AS survival_days
  FROM cohort
)
SELECT
  COUNT(*) AS cohort_size,
  -- Composite risk score distribution
  MIN(composite_risk_score) AS risk_score_min,
  APPROX_QUANTILES(composite_risk_score, 4)[OFFSET(1)] AS risk_score_25th,
  APPROX_QUANTILES(composite_risk_score, 4)[OFFSET(2)] AS risk_score_median,
  APPROX_QUANTILES(composite_risk_score, 4)[OFFSET(3)] AS risk_score_75th,
  MAX(composite_risk_score) AS risk_score_max,
  -- Outcome rates
  ROUND(SUM(hospital_expire_flag) / COUNT(*), 3) AS in_hospital_mortality_rate,
  ROUND(SUM(has_aki) / COUNT(*), 3) AS aki_rate,
  ROUND(SUM(has_ards) / COUNT(*), 3) AS ards_rate,
  -- Median survival days for decedents
  APPROX_QUANTILES(survival_days, 2)[OFFSET(1)] AS median_survival_days_decedents
FROM risk_scores;