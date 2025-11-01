WITH qualifying_admissions AS (
  -- Find all hospital admissions that meet the core criteria
  SELECT
    a.subject_id,
    a.hadm_id,
    a.admittime
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` AS a
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` AS p
    ON a.subject_id = p.subject_id
  WHERE
    -- 1. Male patients
    p.gender = 'M'
    -- 2. Aged 68-78 at admission
    AND (EXTRACT(YEAR FROM a.admittime) - p.anchor_year + p.anchor_age) BETWEEN 68 AND 78
    -- 3. Had an Intracranial Hemorrhage (ICH) diagnosis
    AND EXISTS (
      SELECT 1
      FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` AS dx
      WHERE dx.hadm_id = a.hadm_id
        AND (
          STARTS_WITH(dx.icd_code, 'I61') -- Intracerebral haemorrhage
          OR STARTS_WITH(dx.icd_code, 'I62') -- Other nontraumatic intracranial haemorrhage
          OR STARTS_WITH(dx.icd_code, 'S064') -- Epidural hemorrhage
          OR STARTS_WITH(dx.icd_code, 'S065') -- Traumatic subdural hemorrhage
          OR STARTS_WITH(dx.icd_code, 'S066') -- Traumatic subarachnoid hemorrhage
        )
    )
    -- 4. Had an ICU stay during this admission
    AND EXISTS (
      SELECT 1
      FROM `physionet-data.mimiciv_3_1_icu.icustays` AS icu
      WHERE icu.hadm_id = a.hadm_id
    )
),

first_qualifying_admission AS (
  -- Select only the first qualifying admission for each patient
  SELECT
    subject_id,
    hadm_id
  FROM qualifying_admissions
  QUALIFY ROW_NUMBER() OVER(PARTITION BY subject_id ORDER BY admittime ASC) = 1
),

cohort_with_outcomes AS (
  -- Gather all features and outcomes for the final patient cohort
  SELECT
    fqa.subject_id,
    -- 30-day mortality flag
    CASE
      WHEN p.dod IS NOT NULL AND DATE_DIFF(p.dod, a.admittime, DAY) BETWEEN 0 AND 30
        THEN 1
      ELSE 0
    END AS died_in_30_days,
    -- AKI flag (check for diagnosis in this admission)
    CASE
      WHEN EXISTS (
        SELECT 1
        FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` AS dx
        WHERE dx.hadm_id = fqa.hadm_id
          AND (
            STARTS_WITH(dx.icd_code, 'N17') -- ICD-10 AKI
            OR STARTS_WITH(dx.icd_code, '584') -- ICD-9 AKI
          )
      )
        THEN 1
      ELSE 0
    END AS had_aki,
    -- ARDS flag (check for diagnosis in this admission)
    CASE
      WHEN EXISTS (
        SELECT 1
        FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` AS dx
        WHERE dx.hadm_id = fqa.hadm_id
          AND (
            dx.icd_code = 'J80' -- ICD-10 ARDS
            OR dx.icd_code = '51882' -- ICD-9 ARDS
          )
      )
        THEN 1
      ELSE 0
    END AS had_ards,
    -- Hospital Length of Stay (proxy for composite risk score)
    DATETIME_DIFF(a.dischtime, a.admittime, DAY) AS hospital_los_days,
    -- Survival time in days, only for patients who died
    CASE
      WHEN p.dod IS NOT NULL
        THEN DATE_DIFF(p.dod, a.admittime, DAY)
      ELSE NULL
    END AS survival_days_if_decedent
  FROM first_qualifying_admission AS fqa
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` AS a
    ON fqa.hadm_id = a.hadm_id
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` AS p
    ON fqa.subject_id = p.subject_id
)

-- Final aggregation and calculation of metrics
SELECT
  COUNT(subject_id) AS cohort_size,
  SAFE_DIVIDE(SUM(died_in_30_days), COUNT(subject_id)) * 100 AS mortality_rate_30_day,
  SAFE_DIVIDE(SUM(had_aki), COUNT(subject_id)) * 100 AS aki_rate,
  SAFE_DIVIDE(SUM(had_ards), COUNT(subject_id)) * 100 AS ards_rate,
  APPROX_QUANTILES(hospital_los_days, 100 IGNORE NULLS)[OFFSET(25)] AS composite_risk_score_p25,
  APPROX_QUANTILES(hospital_los_days, 100 IGNORE NULLS)[OFFSET(50)] AS composite_risk_score_p50,
  APPROX_QUANTILES(hospital_los_days, 100 IGNORE NULLS)[OFFSET(75)] AS composite_risk_score_p75,
  APPROX_QUANTILES(survival_days_if_decedent, 100 IGNORE NULLS)[OFFSET(50)] AS median_survival_days_decedents
FROM cohort_with_outcomes;