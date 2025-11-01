WITH
-- Step 1: Select female patients aged 69-79 at the time of admission.
patient_cohort AS (
  SELECT
    p.subject_id,
    p.dod,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    a.hospital_expire_flag,
    EXTRACT(YEAR FROM a.admittime) - p.anchor_year + p.anchor_age AS age
  FROM
    `physionet-data.mimiciv_3_1_hosp.patients` AS p
  INNER JOIN
    `physionet-data.mimiciv_3_1_hosp.admissions` AS a
    ON p.subject_id = a.subject_id
  WHERE
    p.gender = 'F'
    AND (EXTRACT(YEAR FROM a.admittime) - p.anchor_year + p.anchor_age) BETWEEN 69 AND 79
),

-- Step 2: From the initial cohort, identify admissions with an ICH diagnosis.
ich_admissions AS (
  SELECT DISTINCT
    pc.subject_id,
    pc.hadm_id,
    pc.admittime,
    pc.dischtime,
    pc.dod,
    pc.hospital_expire_flag,
    pc.age
  FROM
    patient_cohort AS pc
  INNER JOIN
    `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` AS d
    ON pc.hadm_id = d.hadm_id
  WHERE
    -- ICD-9 codes for ICH
    (d.icd_version = 9 AND (d.icd_code LIKE '430%' OR d.icd_code LIKE '431%' OR d.icd_code LIKE '432%'))
    OR
    -- ICD-10 codes for ICH
    (d.icd_version = 10 AND (d.icd_code LIKE 'I60%' OR d.icd_code LIKE 'I61%' OR d.icd_code LIKE 'I62%'))
),

-- Step 3: Count unique diagnoses for each admission to use as a comorbidity proxy.
comorbidity_counts AS (
  SELECT
    hadm_id,
    COUNT(DISTINCT icd_code) AS num_diagnoses
  FROM
    `physionet-data.mimiciv_3_1_hosp.diagnoses_icd`
  GROUP BY
    hadm_id
),

-- Step 4: Identify admissions that have a diagnosis code for a major complication.
major_complications AS (
  SELECT DISTINCT
    hadm_id
  FROM
    `physionet-data.mimiciv_3_1_hosp.diagnoses_icd`
  WHERE
    -- ICD-9 codes for major complications
    (
      icd_version = 9 AND (
        icd_code LIKE '99591%' OR -- Sepsis
        icd_code LIKE '99592%' OR -- Severe sepsis
        icd_code LIKE '78552%' OR -- Septic shock
        icd_code LIKE '584%' OR -- Acute kidney failure
        icd_code LIKE '51881%' OR -- Acute respiratory failure
        icd_code LIKE '51884%' OR -- Acute and chronic respiratory failure
        icd_code LIKE '4151%' -- Pulmonary embolism and infarction
      )
    )
    OR
    -- ICD-10 codes for major complications
    (
      icd_version = 10 AND (
        icd_code LIKE 'A40%' OR -- Streptococcal sepsis
        icd_code LIKE 'A41%' OR -- Other sepsis
        icd_code LIKE 'R65.2%' OR -- Severe sepsis
        icd_code LIKE 'N17%' OR -- Acute kidney failure
        icd_code LIKE 'J96.0%' OR -- Acute respiratory failure
        icd_code LIKE 'J96.2%' OR -- Acute and chronic respiratory failure
        icd_code LIKE 'I26%' -- Pulmonary embolism
      )
    )
),

-- Step 5: Assemble features for each admission: risk score, and outcome flags.
cohort_features AS (
  SELECT
    ia.hadm_id,
    -- Define composite risk score: age + number of diagnoses
    ia.age + COALESCE(cc.num_diagnoses, 0) AS composite_risk_score,
    -- Flag for 30-day mortality (1 if true, 0 if false)
    CASE
      WHEN ia.dod IS NOT NULL AND ia.dod <= TIMESTAMP_ADD(ia.admittime, INTERVAL 30 DAY)
      THEN 1
      ELSE 0
    END AS is_dead_30_days,
    -- Flag for major complication (1 if true, 0 if false)
    CASE
      WHEN mc.hadm_id IS NOT NULL THEN 1
      ELSE 0
    END AS has_major_complication,
    -- Calculate LOS in days only for patients who survived the hospital stay
    CASE
      WHEN ia.hospital_expire_flag = 0 THEN TIMESTAMP_DIFF(ia.dischtime, ia.admittime, DAY)
      ELSE NULL
    END AS survivor_los_days
  FROM
    ich_admissions AS ia
  LEFT JOIN
    comorbidity_counts AS cc
    ON ia.hadm_id = cc.hadm_id
  LEFT JOIN
    major_complications AS mc
    ON ia.hadm_id = mc.hadm_id
),

-- Step 6: Stratify admissions into 5 quintiles based on the composite risk score.
risk_quintiles AS (
  SELECT
    *,
    NTILE(5) OVER (ORDER BY composite_risk_score) AS risk_quintile
  FROM
    cohort_features
)

-- Final Step: Group by quintile and calculate the final metrics.
SELECT
  risk_quintile,
  COUNT(hadm_id) AS n,
  ROUND(AVG(is_dead_30_days) * 100, 2) AS mortality_30_day_pct,
  ROUND(AVG(has_major_complication) * 100, 2) AS major_complication_pct,
  -- Calculate the median (50th percentile) of survivor LOS, ignoring nulls
  APPROX_QUANTILES(survivor_los_days, 100)[OFFSET(50)] AS median_survivor_los_days
FROM
  risk_quintiles
GROUP BY
  risk_quintile
ORDER BY
  risk_quintile;