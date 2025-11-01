WITH
  -- CTE to identify all hospital admissions that are considered surgical by service type
  surgical_admissions AS (
    SELECT DISTINCT
      hadm_id
    FROM `physionet-data.mimiciv_3_1_hosp.services`
    WHERE
      curr_service IN (
        'CSURG', -- Cardiac Surgery
        'NSURG', -- Neurosurgery
        'PSURG', -- Plastic Surgery
        'SURG', -- General Surgery
        'TSURG', -- Thoracic Surgery
        'VSURG', -- Vascular Surgery
        'ORTHO', -- Orthopedics
        'TRAUM', -- Trauma
        'GU', -- Urology
        'GYN', -- Gynecology
        'ENT', -- Ear, Nose, Throat
        'DENT' -- Dentistry
      )
  ),
  -- CTE to define the patient cohort and calculate LOS and discharge category
  cohort AS (
    SELECT
      adm.hadm_id,
      -- Calculate LOS in integer days
      DATETIME_DIFF(adm.dischtime, adm.admittime, DAY) AS los_days,
      -- Categorize discharge location into the groups of interest
      CASE
        WHEN adm.hospital_expire_flag = 1
        THEN 'In-Hospital Death'
        WHEN adm.discharge_location IN ('HOME', 'HOME HEALTH CARE')
        THEN 'Home'
        WHEN adm.discharge_location IN (
          'SKILLED NURSING FACILITY', 'REHAB/DISTINCT PART HOSP', 'LONG TERM CARE HOSPITAL'
        )
        THEN 'Facility'
        ELSE 'Other'
      END AS discharge_category
    FROM `physionet-data.mimiciv_3_1_hosp.admissions` AS adm
    -- Join to patients to get demographics (gender, age)
    INNER JOIN
      `physionet-data.mimiciv_3_1_hosp.patients` AS pat ON adm.subject_id = pat.subject_id
    -- Use an INNER JOIN to include only surgical admissions
    INNER JOIN
      surgical_admissions AS sa ON adm.hadm_id = sa.hadm_id
    WHERE
      -- 1. Filter for female patients
      pat.gender = 'F'
      -- 2. Filter for age at admission between 70 and 80 (inclusive)
      AND (EXTRACT(YEAR FROM adm.admittime) - pat.anchor_year + pat.anchor_age) BETWEEN 70 AND 80
      -- 3. Ensure dischtime is available to calculate LOS
      AND adm.dischtime IS NOT NULL
  )
-- Final aggregation to calculate counts and proportions
SELECT
  discharge_category,
  COUNT(hadm_id) AS total_admissions,
  COUNTIF(los_days >= 7) AS admissions_los_ge_7,
  SAFE_DIVIDE(COUNTIF(los_days >= 7), COUNT(hadm_id)) AS proportion_los_ge_7,
  COUNTIF(los_days >= 14) AS admissions_los_ge_14,
  SAFE_DIVIDE(COUNTIF(los_days >= 14), COUNT(hadm_id)) AS proportion_los_ge_14
FROM cohort
-- Filter out admissions that do not fall into our categories of interest
WHERE
  discharge_category IN ('Home', 'Facility', 'In-Hospital Death')
GROUP BY
  discharge_category
ORDER BY
  discharge_category;