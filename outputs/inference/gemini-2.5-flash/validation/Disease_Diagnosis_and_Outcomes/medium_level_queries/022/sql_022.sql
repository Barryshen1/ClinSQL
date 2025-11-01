WITH
  -- 1. Identify admissions with a "sepsis without septic shock" diagnosis
  sepsis_diagnoses AS (
    SELECT DISTINCT hadm_id
    FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd`
    WHERE
      (
        icd_version = 9
        AND (
          icd_code LIKE '038%'      -- Septicemia
          OR icd_code IN ('99591', '99592') -- Sepsis, Severe sepsis
        )
      )
      OR (
        icd_version = 10
        AND (
          icd_code LIKE 'A40%'      -- Streptococcal sepsis
          OR icd_code LIKE 'A41%'   -- Other sepsis
          OR icd_code = 'R6520'     -- Severe sepsis without septic shock
        )
      )
  ),

  -- 2. Identify admissions with a "septic shock" diagnosis (to be excluded)
  septic_shock_diagnoses AS (
    SELECT DISTINCT hadm_id
    FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd`
    WHERE
      (icd_version = 9 AND icd_code = '78552') -- Septic shock
      OR (icd_version = 10 AND icd_code = 'R6521') -- Severe sepsis with septic shock
  ),

  -- 3. Filter for admissions that have sepsis but NOT septic shock
  sepsis_no_shock_admissions AS (
    SELECT s.hadm_id
    FROM sepsis_diagnoses s
    LEFT JOIN septic_shock_diagnoses ss ON s.hadm_id = ss.hadm_id
    WHERE ss.hadm_id IS NULL
  ),

  -- 4. Determine day-1 ICU status for each hospital admission
  day1_icu_status AS (
    SELECT DISTINCT
      ad.hadm_id,
      TRUE AS in_icu_day1
    FROM `physionet-data.mimiciv_3_1_hosp.admissions` ad
    JOIN `physionet-data.mimiciv_3_1_icu.icustays` icu
      ON ad.hadm_id = icu.hadm_id
    WHERE
      -- ICU stay intime must be within the first 24 hours of hospital admission
      icu.intime BETWEEN ad.admittime AND DATETIME_ADD(ad.admittime, INTERVAL 1 DAY)
  ),

  -- 5. Build the main cohort with demographics, hospital stay details, LOS, and day-1 ICU presence
  cohort_data AS (
    SELECT
      p.subject_id,
      ad.hadm_id,
      p.gender,
      p.anchor_age,
      ad.admittime,
      ad.dischtime,
      DATETIME_DIFF(ad.dischtime, ad.admittime, DAY) AS los_days, -- LOS in full days
      ad.hospital_expire_flag,
      CASE
        WHEN d1icu.in_icu_day1 IS TRUE THEN 'Yes'
        ELSE 'No'
      END AS day1_icu_presence_status,
      CASE
        WHEN DATETIME_DIFF(ad.dischtime, ad.admittime, DAY) <= 7 THEN 'LOS <= 7 Days'
        ELSE 'LOS > 7 Days'
      END AS los_category
    FROM `physionet-data.mimiciv_3_1_hosp.admissions` ad
    JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
      ON ad.subject_id = p.subject_id
    JOIN sepsis_no_shock_admissions sna -- Filter for sepsis without septic shock
      ON ad.hadm_id = sna.hadm_id
    LEFT JOIN day1_icu_status d1icu -- Left join to include admissions without day-1 ICU stay
      ON ad.hadm_id = d1icu.hadm_id
    WHERE
      p.gender = 'M'
      AND p.anchor_age BETWEEN 50 AND 60 -- Filter for male patients aged 50-60
  )

-- 6. Aggregate results by LOS category and Day-1 ICU status
SELECT
  los_category,
  day1_icu_presence_status,
  COUNT(DISTINCT hadm_id) AS num_admissions,
  SUM(hospital_expire_flag) AS num_deaths,
  (SUM(hospital_expire_flag) * 100.0 / COUNT(DISTINCT hadm_id)) AS in_hospital_mortality_percent,
  APPROX_QUANTILES(los_days, 100)[OFFSET(50)] AS median_los_days -- Calculate median LOS
FROM cohort_data
GROUP BY
  los_category,
  day1_icu_presence_status
ORDER BY
  los_category,
  day1_icu_presence_status;