WITH
-- Part 1: Define the baseline cohort of all female patients aged 59-69
baseline_cohort AS (
  SELECT
    a.admittime,
    p.dod
  FROM
    `physionet-data.mimiciv_3_1_hosp.patients` AS p
  JOIN
    `physionet-data.mimiciv_3_1_hosp.admissions` AS a
    ON p.subject_id = a.subject_id
  WHERE
    p.gender = 'F'
    AND p.anchor_age BETWEEN 59 AND 69
),
-- Calculate the baseline 30-day mortality for this cohort
baseline_mortality AS (
  SELECT
    '0 - Baseline (All Females 59-69)' AS report_group,
    NULL AS num_patients,
    AVG(
      CASE
        WHEN p.dod IS NOT NULL AND DATETIME_DIFF(p.dod, p.admittime, DAY) BETWEEN 0 AND 30
        THEN 1.0
        ELSE 0.0
      END
    ) AS thirty_day_mortality_rate,
    NULL AS cardiovascular_complication_rate,
    NULL AS neurologic_complication_rate,
    NULL AS median_survivor_los_days
  FROM
    baseline_cohort AS p
),
-- Part 2: Identify the primary cohort of interest: first admission for cardiac arrest
cardiac_arrest_admissions AS (
  SELECT
    p.subject_id,
    a.hadm_id,
    p.anchor_age,
    a.admittime,
    a.dischtime,
    a.hospital_expire_flag,
    p.dod,
    ROW_NUMBER() OVER (PARTITION BY p.subject_id ORDER BY a.admittime) AS rn
  FROM
    `physionet-data.mimiciv_3_1_hosp.patients` AS p
  JOIN
    `physionet-data.mimiciv_3_1_hosp.admissions` AS a
    ON p.subject_id = a.subject_id
  WHERE
    p.gender = 'F'
    AND p.anchor_age BETWEEN 59 AND 69
    AND EXISTS (
      SELECT 1
      FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` AS dx
      JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` AS ddx
        ON dx.icd_code = ddx.icd_code AND dx.icd_version = ddx.icd_version
      WHERE
        a.hadm_id = dx.hadm_id
        AND (
            LOWER(ddx.long_title) LIKE '%cardiac arrest%'
            OR dx.icd_code IN ('427.5', 'I46', 'I46.2', 'I46.8', 'I46.9')
        )
    )
),
-- Part 3: For each admission, identify comorbidities (for risk score) and complications
diagnoses_by_hadm AS (
  SELECT
    dx.hadm_id,
    -- Comorbidities for risk score
    MAX(CASE WHEN LOWER(ddx.long_title) LIKE '%diabetes mellitus%' THEN 1 ELSE 0 END) AS has_diabetes,
    MAX(CASE WHEN LOWER(ddx.long_title) LIKE '%chronic kidney disease%' THEN 1 ELSE 0 END) AS has_ckd,
    MAX(CASE WHEN LOWER(ddx.long_title) LIKE '%congestive heart failure%' THEN 1 ELSE 0 END) AS has_chf,
    -- Cardiovascular complications
    MAX(CASE WHEN
        LOWER(ddx.long_title) LIKE '%myocardial infarction%' OR
        LOWER(ddx.long_title) LIKE '%cardiogenic shock%' OR
        LOWER(ddx.long_title) LIKE '%cerebrovascular accident%' OR
        LOWER(ddx.long_title) LIKE '%pulmonary embolism%'
        THEN 1 ELSE 0 END
    ) AS has_cardiovasc_complication,
    -- Neurologic complications
    MAX(CASE WHEN
        LOWER(ddx.long_title) LIKE '%anoxic brain injury%' OR
        LOWER(ddx.long_title) LIKE '%hypoxic-ischemic encephalopathy%' OR
        LOWER(ddx.long_title) LIKE '%cerebral edema%' OR
        LOWER(ddx.long_title) LIKE '%seizure%' OR
        LOWER(ddx.long_title) LIKE '%status epilepticus%' OR
        LOWER(ddx.long_title) LIKE '%coma%'
        THEN 1 ELSE 0 END
    ) AS has_neuro_complication
  FROM
    `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` AS dx
  JOIN
    `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` AS ddx
    ON dx.icd_code = ddx.icd_code AND dx.icd_version = ddx.icd_version
  WHERE dx.hadm_id IN (SELECT hadm_id FROM cardiac_arrest_admissions WHERE rn = 1)
  GROUP BY
    dx.hadm_id
),
-- Part 4: Calculate risk score and stratify into quartiles
cohort_with_scores AS (
  SELECT
    c.hadm_id,
    c.admittime,
    c.dischtime,
    c.dod,
    c.hospital_expire_flag,
    d.has_cardiovasc_complication,
    d.has_neuro_complication,
    -- Calculate composite risk score
    (c.anchor_age - 59) + COALESCE(d.has_diabetes, 0) + COALESCE(d.has_ckd, 0) + COALESCE(d.has_chf, 0) AS composite_risk_score
  FROM
    cardiac_arrest_admissions AS c
  LEFT JOIN
    diagnoses_by_hadm AS d ON c.hadm_id = d.hadm_id
  WHERE
    c.rn = 1 -- Use only the first admission for each patient
),
cohort_with_quartiles AS (
  SELECT
    *,
    NTILE(4) OVER (ORDER BY composite_risk_score) AS risk_quartile
  FROM
    cohort_with_scores
),
-- Part 5: Aggregate metrics by risk quartile
quartile_results AS (
  SELECT
    risk_quartile,
    COUNT(DISTINCT hadm_id) AS num_patients,
    AVG(
      CASE
        WHEN dod IS NOT NULL AND DATETIME_DIFF(dod, admittime, DAY) BETWEEN 0 AND 30
        THEN 1.0
        ELSE 0.0
      END
    ) AS thirty_day_mortality_rate,
    AVG(has_cardiovasc_complication) AS cardiovascular_complication_rate,
    AVG(has_neuro_complication) AS neurologic_complication_rate,
    APPROX_QUANTILES(
      CASE
        WHEN hospital_expire_flag = 0 THEN DATETIME_DIFF(dischtime, admittime, DAY)
      END, 100
    )[OFFSET(50)] AS median_survivor_los_days
  FROM
    cohort_with_quartiles
  GROUP BY
    risk_quartile
)
-- Final Output: Combine baseline and quartile results
SELECT
  *
FROM
  baseline_mortality
UNION ALL
SELECT
  CONCAT('Quartile ', risk_quartile) AS report_group,
  num_patients,
  thirty_day_mortality_rate,
  cardiovascular_complication_rate,
  neurologic_complication_rate,
  median_survivor_los_days
FROM
  quartile_results
ORDER BY
  report_group;