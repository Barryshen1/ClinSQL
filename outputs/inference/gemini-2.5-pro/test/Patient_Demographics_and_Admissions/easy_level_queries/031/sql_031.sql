WITH
  -- Step 1: Identify all ICD codes for 'heart failure'
  hf_icd AS (
    SELECT
      icd_code,
      icd_version
    FROM `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses`
    WHERE
      LOWER(long_title) LIKE '%heart failure%'
  ),
  -- Get all hospital admission IDs (hadm_id) with a heart failure diagnosis
  hf_admissions AS (
    SELECT DISTINCT
      hadm_id
    FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd`
    WHERE
      (icd_code, icd_version) IN (
        SELECT
          (icd_code, icd_version)
        FROM hf_icd
      )
  ),
  -- Step 2: For every admission, find the start time of the next one
  all_admissions_with_next AS (
    SELECT
      subject_id,
      hadm_id,
      admittime,
      dischtime,
      LEAD(admittime) OVER (PARTITION BY subject_id ORDER BY admittime) AS next_admittime
    FROM `physionet-data.mimiciv_3_1_hosp.admissions`
  ),
  -- Step 3: Identify the first HF admission for each patient in the specified cohort
  cohort_first_hf_admission AS (
    SELECT
      all_adm.subject_id,
      all_adm.dischtime,
      all_adm.next_admittime,
      -- Rank HF admissions by time to find the first one for each patient
      ROW_NUMBER() OVER (PARTITION BY p.subject_id ORDER BY all_adm.admittime) AS rn
    FROM all_admissions_with_next AS all_adm
    INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` AS p
      ON all_adm.subject_id = p.subject_id
    -- This join ensures we only consider heart failure admissions
    INNER JOIN hf_admissions AS hf
      ON all_adm.hadm_id = hf.hadm_id
    WHERE
      -- Filter for female patients
      p.gender = 'F'
      -- Filter for patients aged 38-48 at the time of admission
      AND DATETIME_DIFF(all_adm.admittime, DATETIME(p.anchor_year, 1, 1, 0, 0, 0), YEAR) + p.anchor_age BETWEEN 38 AND 48
  ),
  -- Step 4: For each patient's first HF admission, flag if they were readmitted within 30 days
  readmission_flags AS (
    SELECT
      subject_id,
      -- If the next admission is within 30 days of discharge, flag as 1, else 0.
      CASE
        WHEN next_admittime IS NOT NULL AND DATETIME_DIFF(next_admittime, dischtime, DAY) <= 30
          THEN 1
        ELSE 0
      END AS is_readmitted_30d
    FROM cohort_first_hf_admission
    -- We only care about the very first HF admission (rn=1) for each patient
    WHERE
      rn = 1
  )
-- Step 5: Calculate the average of the flags to get the final rate
SELECT
  AVG(is_readmitted_30d) AS avg_30d_readmission_rate
FROM readmission_flags;