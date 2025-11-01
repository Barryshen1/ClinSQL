WITH
  patients_cohort AS (
    -- Step 1: Select male patients aged 50-60
    SELECT
      subject_id
    FROM
      `physionet-data.mimiciv_3_1_hosp.patients`
    WHERE
      gender = 'M'
      AND anchor_age BETWEEN 50 AND 60
  ),
  admissions_with_dx AS (
    -- Step 2: Find admissions for the patient cohort with a diagnosis of Chest Pain or AMI
    SELECT DISTINCT
      adm.subject_id,
      adm.hadm_id
    FROM
      `physionet-data.mimiciv_3_1_hosp.admissions` AS adm
    INNER JOIN patients_cohort AS p
      ON adm.subject_id = p.subject_id
    INNER JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` AS dx
      ON adm.hadm_id = dx.hadm_id
    WHERE
      (dx.icd_version = 9 AND (dx.icd_code LIKE '410%' OR dx.icd_code LIKE '786.5%'))
      OR (dx.icd_version = 10 AND (dx.icd_code LIKE 'I21%' OR dx.icd_code LIKE 'I22%' OR dx.icd_code LIKE 'R07%'))
  ),
  first_troponin AS (
    -- Step 3: Identify the first hs-TnT (itemid 52598) for each admission
    SELECT
      hadm_id,
      valuenum,
      ROW_NUMBER() OVER (PARTITION BY hadm_id ORDER BY charttime) AS rn
    FROM
      `physionet-data.mimiciv_3_1_hosp.labevents`
    WHERE
      itemid = 52598 -- Troponin T, High Sensitivity
      AND valuenum IS NOT NULL
  ),
  final_cohort AS (
    -- Step 4: Join the cohorts and filter for initial hs-TnT > 0.014 ng/mL
    SELECT
      adx.subject_id,
      adx.hadm_id,
      ft.valuenum AS initial_tnt
    FROM
      admissions_with_dx AS adx
    INNER JOIN first_troponin AS ft
      ON adx.hadm_id = ft.hadm_id
    WHERE
      ft.rn = 1 -- Only the first measurement
      AND ft.valuenum > 0.014 -- Value > ULN
  )
-- Step 5: Calculate final statistics from the cohort
SELECT
  COUNT(DISTINCT subject_id) AS patient_count,
  COUNT(DISTINCT hadm_id) AS admission_count,
  AVG(initial_tnt) AS mean_initial_tnt,
  APPROX_QUANTILES(initial_tnt, 100) [OFFSET(50)] AS median_initial_tnt,
  (
    APPROX_QUANTILES(initial_tnt, 100) [OFFSET(75)] - APPROX_QUANTILES(initial_tnt, 100) [OFFSET(25)]
  ) AS iqr_initial_tnt
FROM
  final_cohort;