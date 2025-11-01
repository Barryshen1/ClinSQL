WITH
  -- Step 1 & 2: Identify the first hospital admission for female patients aged 50-60 at time of admission
  first_admissions AS (
    SELECT
      p.subject_id,
      a.hadm_id
    FROM
      `physionet-data.mimiciv_3_1_hosp.patients` AS p
      JOIN (
        SELECT
          subject_id,
          hadm_id,
          admittime,
          ROW_NUMBER() OVER (PARTITION BY subject_id ORDER BY admittime ASC) AS rn
        FROM
          `physionet-data.mimiciv_3_1_hosp.admissions`
      ) AS a
        ON p.subject_id = a.subject_id
    WHERE
      p.gender = 'F'
      -- Calculate age at admission for better accuracy
      AND (p.anchor_age + EXTRACT(YEAR FROM a.admittime) - p.anchor_year) BETWEEN 50 AND 60
      AND a.rn = 1
  ),
  -- Step 3: Identify the first ICU stay within those first admissions
  first_icu_stays AS (
    SELECT
      fa.hadm_id,
      icu.los
    FROM
      first_admissions AS fa
      JOIN (
        SELECT
          hadm_id,
          los,
          intime,
          ROW_NUMBER() OVER (PARTITION BY hadm_id ORDER BY intime ASC) AS rn
        FROM
          `physionet-data.mimiciv_3_1_icu.icustays`
      ) AS icu
        ON fa.hadm_id = icu.hadm_id
    WHERE
      icu.rn = 1
  ),
  -- Step 4: Identify hospital admissions where anticoagulants were prescribed
  anticoagulant_admissions AS (
    SELECT DISTINCT
      hadm_id
    FROM
      `physionet-data.mimiciv_3_1_hosp.prescriptions`
    WHERE
      LOWER(drug) LIKE '%heparin%'
      OR LOWER(drug) LIKE '%warfarin%'
      OR LOWER(drug) LIKE '%coumadin%'
      OR LOWER(drug) LIKE '%enoxaparin%'
      OR LOWER(drug) LIKE '%lovenox%'
      OR LOWER(drug) LIKE '%apixaban%'
      OR LOWER(drug) LIKE '%eliquis%'
      OR LOWER(drug) LIKE '%rivaroxaban%'
      OR LOWER(drug) LIKE '%xarelto%'
      OR LOWER(drug) LIKE '%dabigatran%'
      OR LOWER(drug) LIKE '%pradaxa%'
      OR LOWER(drug) LIKE '%fondaparinux%'
      OR LOWER(drug) LIKE '%argatroban%'
      OR LOWER(drug) LIKE '%bivalirudin%'
  )
-- Step 5: Join the cohorts and calculate the median LOS
SELECT
  APPROX_QUANTILES(icu.los, 100) [OFFSET(50)] AS median_icu_los_days
FROM
  first_icu_stays AS icu
  INNER JOIN anticoagulant_admissions AS ac
    ON icu.hadm_id = ac.hadm_id;