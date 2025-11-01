WITH
-- base admissions for female patients aged 59-69
female_admissions AS (
  SELECT
    a.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    a.deathtime,
    a.hospital_expire_flag,
    p.anchor_age
  FROM
    `physionet-data.mimiciv_3_1_hosp.admissions` a
    JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
      USING(subject_id)
  WHERE
    p.gender = 'F'
    AND p.anchor_age BETWEEN 59 AND 69
),

-- keep only admissions with a heart-failure diagnosis (ICD-9 428*, ICD-10 I50*, or long_title match)
hf_admissions AS (
  SELECT DISTINCT
    fa.*
  FROM
    female_admissions fa
  JOIN
    `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
    ON fa.hadm_id = d.hadm_id
  JOIN
    `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` dicd
    ON d.icd_code = dicd.icd_code
    AND d.icd_version = dicd.icd_version
  WHERE
    (
      -- textual match (covers many variants)
      LOWER(dicd.long_title) LIKE '%heart failure%'
      -- explicit code patterns for common HF codes (ICD-9 428*, ICD-10 I50*)
      OR (d.icd_version = 9 AND SAFE_CAST(d.icd_code AS STRING) LIKE '428%')
      OR (d.icd_version = 10 AND SAFE_CAST(d.icd_code AS STRING) LIKE 'I50%')
    )
),

-- flags per admission for AKI and ARDS (based on diagnoses)
hadm_flags AS (
  SELECT
    ha.subject_id,
    ha.hadm_id,
    ha.admittime,
    ha.dischtime,
    ha.deathtime,
    ha.hospital_expire_flag,
    -- AKI flag: ICD-9 584*, ICD-10 N17*, or textual match
    IF(EXISTS (
      SELECT 1 FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
      JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` dicd
        ON d.icd_code = dicd.icd_code AND d.icd_version = dicd.icd_version
      WHERE d.hadm_id = ha.hadm_id
        AND (
          LOWER(dicd.long_title) LIKE '%acute kidney%'
          OR LOWER(dicd.long_title) LIKE '%acute renal%'
          OR (d.icd_version = 9 AND SAFE_CAST(d.icd_code AS STRING) LIKE '584%')
          OR (d.icd_version = 10 AND SAFE_CAST(d.icd_code AS STRING) LIKE 'N17%')
        )
    ), 1, 0) AS aki_flag,
    -- ARDS flag: textual match for ARDS / acute respiratory distress
    IF(EXISTS (
      SELECT 1 FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
      JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` dicd
        ON d.icd_code = dicd.icd_code AND d.icd_version = dicd.icd_version
      WHERE d.hadm_id = ha.hadm_id
        AND (
          LOWER(dicd.long_title) LIKE '%acute respiratory%'
          OR LOWER(dicd.long_title) LIKE '%ards%'
          -- including some ICD code patterns could be added but textual match covers common labels
        )
    ), 1, 0) AS ards_flag
  FROM
    hf_admissions ha
),

-- compute composite score and survival (days) for in-hospital deaths
hadm_scores AS (
  SELECT
    hf.*,
    (hf.hospital_expire_flag + hf.aki_flag + hf.ards_flag) AS composite_score,
    -- survival in days (fractional). Only computed for in-hospital deaths with a deathtime.
    CASE
      WHEN hf.hospital_expire_flag = 1 AND hf.deathtime IS NOT NULL AND hf.deathtime >= hf.admittime
        THEN SAFE_DIVIDE(TIMESTAMP_DIFF(hf.deathtime, hf.admittime, HOUR), 24.0)
      ELSE NULL
    END AS survival_days
  FROM
    hadm_flags hf
)

SELECT
  COUNT(*) AS cohort_n,
  SUM(hospital_expire_flag) AS mortality_n,
  ROUND(100.0 * SAFE_DIVIDE(SUM(hospital_expire_flag), COUNT(*)), 2) AS mortality_pct,
  SUM(aki_flag) AS aki_n,
  ROUND(100.0 * SAFE_DIVIDE(SUM(aki_flag), COUNT(*)), 2) AS aki_pct,
  SUM(ards_flag) AS ards_n,
  ROUND(100.0 * SAFE_DIVIDE(SUM(ards_flag), COUNT(*)), 2) AS ards_pct,
  -- median survival among in-hospital deaths (days)
  (SELECT IFNULL(quant, NULL) FROM UNNEST([(
     SELECT APPROX_QUANTILES(survival_days, 2)[OFFSET(1)]
     FROM hadm_scores
     WHERE survival_days IS NOT NULL
  )]) AS quant) AS median_survival_days_among_inhospital_deaths,
  -- composite risk score distribution
  MIN(composite_score) AS composite_min,
  (SELECT arr[OFFSET(25)] FROM (SELECT APPROX_QUANTILES(composite_score, 100) AS arr FROM hadm_scores)) AS composite_p25,
  (SELECT arr[OFFSET(50)] FROM (SELECT APPROX_QUANTILES(composite_score, 100) AS arr FROM hadm_scores)) AS composite_median,
  (SELECT arr[OFFSET(75)] FROM (SELECT APPROX_QUANTILES(composite_score, 100) AS arr FROM hadm_scores)) AS composite_p75,
  (SELECT arr[OFFSET(90)] FROM (SELECT APPROX_QUANTILES(composite_score, 100) AS arr FROM hadm_scores)) AS composite_p90,
  MAX(composite_score) AS composite_max
FROM
  hadm_scores;