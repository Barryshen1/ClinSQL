WITH cohort AS (
  -- Select female inpatients aged 59-69 with heart failure
  SELECT
    adm.subject_id,
    adm.hadm_id,
    pat.anchor_age,
    pat.gender,
    adm.admittime,
    adm.dischtime,
    adm.deathtime,
    adm.hospital_expire_flag
  FROM
    `physionet-data.mimiciv_3_1_hosp.admissions` adm
    JOIN `physionet-data.mimiciv_3_1_hosp.patients` pat
      ON adm.subject_id = pat.subject_id
    JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` dx
      ON adm.hadm_id = dx.hadm_id
    -- Heart failure ICD codes: ICD-10 I50.x, ICD-9 428.x
    WHERE
      pat.gender = 'F'
      AND pat.anchor_age BETWEEN 59 AND 69
      AND (
        (dx.icd_version = 9 AND dx.icd_code LIKE '428%')
        OR (dx.icd_version = 10 AND dx.icd_code LIKE 'I50%')
      )
),
outcomes AS (
  -- For each admission in the cohort, check for AKI and ARDS
  SELECT
    c.*,
    -- AKI ICD codes: ICD-10 N17.x, ICD-9 584.x
    CASE WHEN EXISTS (
      SELECT 1 FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` dx
      WHERE dx.hadm_id = c.hadm_id
        AND (
          (dx.icd_version = 9 AND dx.icd_code LIKE '584%')
          OR (dx.icd_version = 10 AND dx.icd_code LIKE 'N17%')
        )
    ) THEN 1 ELSE 0 END AS has_aki,
    -- ARDS ICD codes: ICD-10 J80, ICD-9 518.82
    CASE WHEN EXISTS (
      SELECT 1 FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` dx
      WHERE dx.hadm_id = c.hadm_id
        AND (
          (dx.icd_version = 9 AND dx.icd_code = '51882')
          OR (dx.icd_version = 10 AND dx.icd_code = 'J80')
        )
    ) THEN 1 ELSE 0 END AS has_ards
  FROM cohort c
),
risk_scores AS (
  SELECT
    *,
    -- Composite risk score: sum of binary indicators
    hospital_expire_flag + has_aki + has_ards AS risk_score,
    -- Survival time in days for deaths
    CASE
      WHEN hospital_expire_flag = 1 AND deathtime IS NOT NULL THEN DATETIME_DIFF(deathtime, admittime, DAY)
      WHEN hospital_expire_flag = 1 AND deathtime IS NULL THEN DATETIME_DIFF(dischtime, admittime, DAY)
      ELSE NULL
    END AS survival_days
  FROM outcomes
),
summary AS (
  SELECT
    COUNT(*) AS n_patients,
    SUM(hospital_expire_flag) / COUNT(*) AS mortality_rate,
    SUM(has_aki) / COUNT(*) AS aki_rate,
    SUM(has_ards) / COUNT(*) AS ards_rate,
    -- Median survival among deaths
    APPROX_QUANTILES(survival_days, 2)[OFFSET(1)] AS median_survival_days,
    -- Composite risk score distribution
    MIN(risk_score) AS risk_score_min,
    APPROX_QUANTILES(risk_score, 4)[OFFSET(1)] AS risk_score_p25,
    APPROX_QUANTILES(risk_score, 4)[OFFSET(2)] AS risk_score_median,
    APPROX_QUANTILES(risk_score, 4)[OFFSET(3)] AS risk_score_p75,
    APPROX_QUANTILES(risk_score, 10)[OFFSET(9)] AS risk_score_p90,
    MAX(risk_score) AS risk_score_max
  FROM risk_scores
  WHERE risk_score IS NOT NULL
)
SELECT
  n_patients,
  mortality_rate,
  aki_rate,
  ards_rate,
  median_survival_days,
  risk_score_min,
  risk_score_p25,
  risk_score_median,
  risk_score_p75,
  risk_score_p90,
  risk_score_max
FROM summary;