WITH
  -- Step 1: Find all hospital admissions with a primary diagnosis of upper GI bleeding
  gi_bleed_admissions AS (
    SELECT
      hadm_id,
      subject_id
    FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd`
    WHERE
      seq_num = 1
      AND icd_code IN (
        -- ICD-10 codes for upper GI bleeding
        'K920',  -- Hematemesis
        'K921',  -- Melena
        'K922',  -- Gastrointestinal hemorrhage, unspecified
        -- ICD-9 codes for upper GI bleeding
        '5780',  -- Hematemesis
        '5781',  -- Melena
        '5789'  -- Hemorrhage of gastrointestinal tract, unspecified
      )
  ),
  -- Step 2: Identify the specific patient demographic cohort
  patient_cohort AS (
    SELECT
      subject_id
    FROM `physionet-data.mimiciv_3_1_hosp.patients`
    WHERE
      gender = 'M'
      AND anchor_age = 70
  ),
  -- Step 3: Calculate length of stay for the intersection of the above cohorts
  admission_los AS (
    SELECT
      -- Calculate LOS in fractional days for better precision
      DATETIME_DIFF(adm.dischtime, adm.admittime, HOUR) / 24.0 AS los_days
    FROM `physionet-data.mimiciv_3_1_hosp.admissions` AS adm
    INNER JOIN gi_bleed_admissions AS gba
      ON adm.hadm_id = gba.hadm_id
    INNER JOIN patient_cohort AS pc
      ON adm.subject_id = pc.subject_id
    -- Ensure dischtime is after admittime to avoid negative LOS values
    WHERE
      adm.dischtime > adm.admittime
  )
-- Step 4: Calculate the 75th percentile of the length of stay
SELECT
  APPROX_QUANTILES(los_days, 100)[OFFSET(75)] AS p75_hospital_los_days
FROM admission_los;