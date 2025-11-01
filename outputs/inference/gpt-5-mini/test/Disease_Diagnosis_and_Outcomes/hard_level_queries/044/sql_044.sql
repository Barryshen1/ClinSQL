WITH
-- All diagnosis text linked to admissions
diag AS (
  SELECT
    di.subject_id,
    di.hadm_id,
    LOWER(dd.long_title) AS long_title
  FROM
    `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` di
  JOIN
    `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` dd
  ON
    di.icd_code = dd.icd_code
    AND di.icd_version = dd.icd_version
),

-- Identify admissions that meet cohort criteria (female, age 59-69, and cardiac arrest diagnosis)
cohort_base AS (
  SELECT
    a.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    a.deathtime,
    p.anchor_age,
    p.gender,
    DATE(a.admittime) AS admit_date,
    DATE(a.dischtime) AS discharge_date,
    -- death_date prefer admission-level deathtime, else patient-level dod
    DATE(
      COALESCE(
        CAST(a.deathtime AS TIMESTAMP),
        CAST(p.dod AS TIMESTAMP)
      )
    ) AS death_date
  FROM
    `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN
    `physionet-data.mimiciv_3_1_hosp.patients` p
  ON
    a.subject_id = p.subject_id
  WHERE
    p.gender = 'F'
    AND p.anchor_age BETWEEN 59 AND 69
    -- require that this admission has a diagnosis with long_title mentioning 'cardiac arrest'
    AND EXISTS (
      SELECT 1 FROM diag d
      WHERE d.hadm_id = a.hadm_id
        AND d.long_title LIKE '%cardiac arrest%'
    )
),

-- For each admission, compute comorbidity flags and complication flags from diagnoses on that admission
admission_flags AS (
  SELECT
    cb.*,
    -- comorbidity flags (0/1) based on diagnosis text for that admission
    MAX(CASE WHEN d.long_title LIKE '%heart failure%' THEN 1 ELSE 0 END) AS has_heart_failure,
    MAX(CASE WHEN (d.long_title LIKE '%chronic renal%' OR d.long_title LIKE '%chronic kidney%' OR d.long_title LIKE '%renal failure%' OR d.long_title LIKE '%kidney failure%') THEN 1 ELSE 0 END) AS has_ckd,
    MAX(CASE WHEN d.long_title LIKE '%diabetes%' THEN 1 ELSE 0 END) AS has_diabetes,
    MAX(CASE WHEN (d.long_title LIKE '%chronic obstructive%' OR d.long_title LIKE '%copd%' OR d.long_title LIKE '%chronic lung%' OR d.long_title LIKE '%pulmonary disease%') THEN 1 ELSE 0 END) AS has_chronic_pulm,
    MAX(CASE WHEN (d.long_title LIKE '%cerebrovascular%' OR d.long_title LIKE '%stroke%' OR d.long_title LIKE '%transient ischaemic%') THEN 1 ELSE 0 END) AS has_cerebrovascular_disease,
    MAX(CASE WHEN (d.long_title LIKE '%malignancy%' OR d.long_title LIKE '%malignant%' OR d.long_title LIKE '%neoplasm%' OR d.long_title LIKE '%metastatic%') THEN 1 ELSE 0 END) AS has_malignancy,

    -- complication flags (0/1) based on any diagnosis appearing on the admission
    MAX(CASE WHEN (
             d.long_title LIKE '%myocardial infarction%'
          OR d.long_title LIKE '%acute myocardial%'
          OR d.long_title LIKE '%ischemi%'
          OR d.long_title LIKE '%arrhythmia%'
          OR d.long_title LIKE '%cardiac arrest%'  -- include recurrences/coding of cardiac event
        ) THEN 1 ELSE 0 END) AS cardio_complication_flag,

    MAX(CASE WHEN (
             d.long_title LIKE '%stroke%'
          OR d.long_title LIKE '%intracerebral%'
          OR d.long_title LIKE '%cerebral%'
          OR d.long_title LIKE '%anoxic brain%'
          OR d.long_title LIKE '%hypoxic ischemic%'
          OR d.long_title LIKE '%seizure%'
        ) THEN 1 ELSE 0 END) AS neuro_complication_flag

  FROM
    cohort_base cb
  LEFT JOIN
    diag d
  ON
    d.hadm_id = cb.hadm_id
  GROUP BY
    cb.subject_id, cb.hadm_id, cb.admittime, cb.dischtime, cb.deathtime, cb.anchor_age, cb.gender, cb.admit_date, cb.discharge_date, cb.death_date
),

-- Compute composite risk score and LOS and 30-day death flag
admissions_scored AS (
  SELECT
    af.*,
    -- composite score: sum of selected comorbidity flags
    (COALESCE(has_heart_failure,0)
     + COALESCE(has_ckd,0)
     + COALESCE(has_diabetes,0)
     + COALESCE(has_chronic_pulm,0)
     + COALESCE(has_cerebrovascular_disease,0)
     + COALESCE(has_malignancy,0)
    ) AS composite_score,
    -- length of stay in days (integer)
    DATE_DIFF(discharge_date, admit_date, DAY) AS los_days,
    -- death within 30 days of admission (inclusive)
    CASE
      WHEN death_date IS NOT NULL
           AND DATE_DIFF(death_date, admit_date, DAY) BETWEEN 0 AND 30 THEN 1
      ELSE 0
    END AS death_within_30d
  FROM
    admission_flags af
),

-- Assign quartiles based on composite_score (NTILE handles ties)
admissions_quartiled AS (
  SELECT
    *,
    NTILE(4) OVER (ORDER BY composite_score) AS quartile
  FROM
    admissions_scored
),

-- Aggregated metrics per quartile
quartile_stats AS (
  SELECT
    quartile,
    COUNT(1) AS n_admissions,
    SUM(death_within_30d) AS deaths_30d,
    SAFE_DIVIDE(SUM(death_within_30d), COUNT(1)) AS mortality_30d_rate,
    SUM(CASE WHEN cardio_complication_flag = 1 THEN 1 ELSE 0 END) AS n_cardio_complications,
    SAFE_DIVIDE(SUM(CASE WHEN cardio_complication_flag = 1 THEN 1 ELSE 0 END), COUNT(1)) AS cardio_complication_rate,
    SUM(CASE WHEN neuro_complication_flag = 1 THEN 1 ELSE 0 END) AS n_neuro_complications,
    SAFE_DIVIDE(SUM(CASE WHEN neuro_complication_flag = 1 THEN 1 ELSE 0 END), COUNT(1)) AS neuro_complication_rate,
    -- median LOS among survivors within the quartile (approximate median)
    -- note: consider only admissions that did NOT die within 30 days
    APPROX_QUANTILES(IF(death_within_30d = 0, los_days, NULL), 2)[OFFSET(1)] AS median_survivor_los_days
  FROM
    admissions_quartiled
  GROUP BY
    quartile
  ORDER BY
    quartile
),

-- Baseline 30-day mortality among all female 59-69 admissions (regardless of cardiac arrest)
baseline_cohort AS (
  SELECT
    a.hadm_id,
    DATE(a.admittime) AS admit_date,
    DATE(
      COALESCE(
        CAST(a.deathtime AS TIMESTAMP),
        CAST(p.dod AS TIMESTAMP)
      )
    ) AS death_date
  FROM
    `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN
    `physionet-data.mimiciv_3_1_hosp.patients` p
  ON
    a.subject_id = p.subject_id
  WHERE
    p.gender = 'F'
    AND p.anchor_age BETWEEN 59 AND 69
),

baseline_mortality AS (
  SELECT
    COUNT(1) AS n_admissions,
    SUM(CASE WHEN death_date IS NOT NULL AND DATE_DIFF(death_date, admit_date, DAY) BETWEEN 0 AND 30 THEN 1 ELSE 0 END) AS deaths_within_30d,
    SAFE_DIVIDE(SUM(CASE WHEN death_date IS NOT NULL AND DATE_DIFF(death_date, admit_date, DAY) BETWEEN 0 AND 30 THEN 1 ELSE 0 END), COUNT(1)) AS baseline_30d_mortality_rate
  FROM
    baseline_cohort
)

-- Final output: quartile-level stats plus the baseline mortality as an additional row
SELECT
  CONCAT('Q', CAST(qs.quartile AS STRING)) AS quartile,
  qs.n_admissions,
  qs.deaths_30d,
  ROUND(qs.mortality_30d_rate, 4) AS mortality_30d_rate,
  qs.n_cardio_complications,
  ROUND(qs.cardio_complication_rate, 4) AS cardio_complication_rate,
  qs.n_neuro_complications,
  ROUND(qs.neuro_complication_rate, 4) AS neuro_complication_rate,
  qs.median_survivor_los_days
FROM
  quartile_stats qs

UNION ALL

SELECT
  'Baseline_female_59_69' AS quartile,
  bm.n_admissions,
  bm.deaths_within_30d,
  ROUND(bm.baseline_30d_mortality_rate, 4) AS mortality_30d_rate,
  NULL, NULL, NULL, NULL, NULL
FROM
  baseline_mortality bm

ORDER BY
  quartile;