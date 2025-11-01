WITH
-- Step 1: Identify male patients aged 58-68
patients_cohort AS (
  SELECT
    subject_id,
    anchor_age
  FROM `physionet-data.mimiciv_3_1_hosp.patients`
  WHERE
    gender = 'M'
    AND anchor_age BETWEEN 58 AND 68
),

-- Step 2: Identify admissions with a diagnosis of Chest Pain or AMI
diagnoses_cohort AS (
  SELECT DISTINCT
    hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd`
  WHERE
    -- ICD-9 codes for AMI (410.xx) or Chest Pain (786.5x)
    (
      icd_version = 9 AND (
        SUBSTR(icd_code, 1, 3) = '410'
        OR SUBSTR(icd_code, 1, 4) = '7865'
      )
    ) OR
    -- ICD-10 codes for AMI (I21, I22) or Chest Pain (R07)
    (
      icd_version = 10 AND (
        SUBSTR(icd_code, 1, 3) IN ('I21', 'I22')
        OR SUBSTR(icd_code, 1, 3) = 'R07'
      )
    )
),

-- Step 3: Identify admissions where the initial Troponin T was > 0.04 ng/mL
initial_troponin AS (
  SELECT
    hadm_id
  FROM (
    SELECT
      hadm_id,
      valuenum,
      -- Rank Troponin T tests by time for each admission
      ROW_NUMBER() OVER (PARTITION BY hadm_id ORDER BY charttime ASC) AS rn
    FROM
      `physionet-data.mimiciv_3_1_hosp.labevents`
    WHERE
      itemid = 51003 -- d_labitems.label = 'Troponin T'
      AND valuenum IS NOT NULL
      AND hadm_id IS NOT NULL
      -- The unit for itemid 51003 is 'ng/mL'
  )
  WHERE
    rn = 1 -- Filter for the first measurement
    AND valuenum > 0.04
),

-- Step 4: Combine all criteria to form the final cohort of admissions
final_cohort AS (
  SELECT
    adm.subject_id,
    adm.hadm_id,
    adm.hospital_expire_flag,
    pt.anchor_age,
    DATETIME_DIFF(adm.dischtime, adm.admittime, DAY) AS los_days
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` AS adm
  INNER JOIN patients_cohort AS pt
    ON adm.subject_id = pt.subject_id
  INNER JOIN diagnoses_cohort AS dx
    ON adm.hadm_id = dx.hadm_id
  INNER JOIN initial_troponin AS trop
    ON adm.hadm_id = trop.hadm_id
)

-- Step 5: Calculate and display summary statistics for the final cohort
SELECT
  COUNT(DISTINCT subject_id) AS number_of_patients,
  COUNT(DISTINCT hadm_id) AS number_of_admissions,
  -- Mortality Statistics
  SUM(hospital_expire_flag) AS total_in_hospital_deaths,
  AVG(hospital_expire_flag) * 100 AS in_hospital_mortality_rate_percent,
  -- Age Statistics
  AVG(anchor_age) AS mean_age,
  MIN(anchor_age) AS min_age,
  MAX(anchor_age) AS max_age,
  -- Length of Stay Statistics
  AVG(los_days) AS mean_los_days,
  MIN(los_days) AS min_los_days,
  MAX(los_days) AS max_los_days,
  APPROX_QUANTILES(los_days, 100)[OFFSET(25)] AS p25_los_days,
  APPROX_QUANTILES(los_days, 100)[OFFSET(50)] AS median_los_days,
  APPROX_QUANTILES(los_days, 100)[OFFSET(75)] AS p75_los_days
FROM final_cohort;