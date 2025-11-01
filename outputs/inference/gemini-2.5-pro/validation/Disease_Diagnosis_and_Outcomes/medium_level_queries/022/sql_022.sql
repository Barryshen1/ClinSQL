WITH
  -- CTE to define the patient cohort with sepsis (but not septic shock),
  -- and calculate key variables like LOS and day-1 ICU status.
  cohort_data AS (
    SELECT
      adm.hadm_id,
      adm.hospital_expire_flag,
      DATETIME_DIFF(adm.dischtime, adm.admittime, DAY) AS hospital_los_days,
      -- Check if an ICU stay started within 24 hours of hospital admission
      CASE
        WHEN EXISTS (
          SELECT
            1
          FROM `physionet-data.mimiciv_3_1_icu.icustays` AS icu
          WHERE
            icu.hadm_id = adm.hadm_id
            AND icu.intime <= DATETIME_ADD(adm.admittime, INTERVAL 24 HOUR)
        )
        THEN 'ICU on Day 1'
        ELSE 'No ICU on Day 1'
      END AS day1_icu_status
    FROM `physionet-data.mimiciv_3_1_hosp.patients` AS pat
    INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` AS adm
      ON pat.subject_id = adm.subject_id
    WHERE
      -- 1. Filter for patient demographics
      pat.gender = 'M'
      AND pat.anchor_age BETWEEN 50 AND 60
      AND adm.dischtime IS NOT NULL -- Ensure LOS can be calculated
      -- 2. Filter for admissions with a sepsis diagnosis
      AND EXISTS (
        SELECT
          1
        FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` AS dx
        WHERE
          dx.hadm_id = adm.hadm_id
          AND (
            (dx.icd_version = 9 AND dx.icd_code = '99591') -- Sepsis
            OR (dx.icd_version = 10 AND (dx.icd_code LIKE 'A41%' OR dx.icd_code = 'R6520')) -- Sepsis / Severe sepsis
          )
      )
      -- 3. Exclude admissions with a septic shock diagnosis
      AND NOT EXISTS (
        SELECT
          1
        FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` AS dx
        WHERE
          dx.hadm_id = adm.hadm_id
          AND (
            (dx.icd_version = 9 AND dx.icd_code = '78552') -- Septic shock
            OR (dx.icd_version = 10 AND dx.icd_code = 'R6521') -- Severe sepsis with septic shock
          )
      )
  )
-- Final aggregation to report metrics by the specified groups
SELECT
  CASE
    WHEN hospital_los_days <= 7 THEN 'LOS <= 7 Days'
    ELSE 'LOS > 7 Days'
  END AS los_group,
  day1_icu_status,
  COUNT(hadm_id) AS num_admissions,
  -- Calculate in-hospital mortality percentage
  ROUND(AVG(hospital_expire_flag) * 100, 2) AS in_hospital_mortality_pct,
  -- Calculate median hospital LOS using approximate quantiles
  APPROX_QUANTILES(hospital_los_days, 100)[OFFSET(50)] AS median_hospital_los_days
FROM cohort_data
GROUP BY
  los_group,
  day1_icu_status
ORDER BY
  los_group,
  day1_icu_status;