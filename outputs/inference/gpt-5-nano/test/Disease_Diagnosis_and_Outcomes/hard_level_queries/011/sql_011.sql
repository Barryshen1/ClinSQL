WITH cohort_base AS (
  SELECT
    a.subject_id,
    a.hadm_id,
    a.admittime,
    a.deathtime,
    p.anchor_age,
    p.gender,
    -- age bucket: 88–89 -> 1, 90–91 -> 2, 92–93 -> 3, 94–95 -> 4, >=96 -> 5
    CASE
      WHEN p.anchor_age BETWEEN 88 AND 89 THEN 1
      WHEN p.anchor_age BETWEEN 90 AND 91 THEN 2
      WHEN p.anchor_age BETWEEN 92 AND 93 THEN 3
      WHEN p.anchor_age BETWEEN 94 AND 95 THEN 4
      WHEN p.anchor_age >= 96 THEN 5
    END AS age_bucket,
    -- AKI flag: acute kidney injury
    CASE WHEN EXISTS (
      SELECT 1
      FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` di
      JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` dd
        ON di.icd_code = dd.icd_code AND di.icd_version = dd.icd_version
      WHERE di.subject_id = a.subject_id
        AND di.hadm_id = a.hadm_id
        AND LOWER(dd.long_title) LIKE '%acute kidney%'
    ) THEN 1 ELSE 0 END AS aki_flag,
    -- ARDS flag: acute respiratory distress syndrome
    CASE WHEN EXISTS (
      SELECT 1
      FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` di
      JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` dd
        ON di.icd_code = dd.icd_code AND di.icd_version = dd.icd_version
      WHERE di.subject_id = a.subject_id
        AND di.hadm_id = a.hadm_id
        AND LOWER(dd.long_title) LIKE '%acute respiratory distress syndrome%'
    ) THEN 1 ELSE 0 END AS ards_flag
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` AS a
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` AS p
    ON a.subject_id = p.subject_id
  WHERE p.gender = 'F'
    AND p.anchor_age BETWEEN 88 AND 98
    -- AMI requirement: AMI diagnosis for this admission
    AND EXISTS (
      SELECT 1
      FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` di
      JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` dd
        ON di.icd_code = dd.icd_code AND di.icd_version = dd.icd_version
      WHERE di.subject_id = a.subject_id
        AND di.hadm_id = a.hadm_id
        AND LOWER(dd.long_title) LIKE '%acute myocardial infarction%'
    )
    -- Post-ICU: ensure an ICU stay occurred for this admission
    AND EXISTS (
      SELECT 1
      FROM `physionet-data.mimiciv_3_1_icu.icustays` i
      WHERE i.subject_id = a.subject_id
        AND i.hadm_id = a.hadm_id
    )
),
cohort_calc AS (
  SELECT
    subject_id,
    hadm_id,
    admittime,
    deathtime,
    anchor_age,
    gender,
    age_bucket,
    aki_flag,
    ards_flag,
    -- simple composite risk score
    CAST(age_bucket AS FLOAT64) + 2.0 * aki_flag + 2.0 * ards_flag AS risk_score,
    CASE
      WHEN deathtime IS NOT NULL
           AND TIMESTAMP_DIFF(deathtime, admittime, DAY) >= 0
           AND TIMESTAMP_DIFF(deathtime, admittime, DAY) <= 30
      THEN 1 ELSE 0
    END AS death_30d
  FROM cohort_base
),
cohort_with_percentile AS (
  SELECT
    *,
    PERCENT_RANK() OVER (ORDER BY risk_score) AS percentile
  FROM cohort_calc
)
SELECT
  AVG(percentile) AS avg_composite_risk_percentile,
  -- 30-day mortality rate (as percentage)
  AVG(CAST(death_30d AS FLOAT64)) * 100.0 AS cohort_30_day_mortality_rate,
  -- AKI rate
  AVG(CAST(aki_flag AS FLOAT64)) * 100.0 AS aki_rate,
  -- ARDS rate
  AVG(CAST(ards_flag AS FLOAT64)) * 100.0 AS ards_rate,
  -- median survival days of decedents
  (SELECT APPROX_MEDIAN(TIMESTAMP_DIFF(deathtime, admittime, DAY))
     FROM cohort_with_percentile
     WHERE deathtime IS NOT NULL) AS median_survival_days
FROM cohort_with_percentile;