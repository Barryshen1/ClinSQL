WITH
  -- 1. Identify the absolute first ICU stay for eligible patients and collect demographics
  first_icu_stay_cohort AS (
    SELECT
      p.subject_id,
      adm.hadm_id,
      icu.stay_id,
      adm.admittime,
      icu.intime,
      icu.outtime,
      p.anchor_age,
      p.anchor_year,
      (p.anchor_age + (EXTRACT(YEAR FROM icu.intime) - p.anchor_year)) AS age_at_icu_intime,
      adm.hospital_expire_flag,
      ROW_NUMBER() OVER (PARTITION BY p.subject_id ORDER BY icu.intime, icu.stay_id) AS rn_icu_stay
    FROM
      `physionet-data.mimiciv_3_1_hosp.patients` AS p
      JOIN `physionet-data.mimiciv_3_1_hosp.admissions` AS adm ON p.subject_id = adm.subject_id
      JOIN `physionet-data.mimiciv_3_1_icu.icustays` AS icu ON adm.hadm_id = icu.hadm_id
    WHERE
      p.gender = 'M'
      AND (p.anchor_age + (EXTRACT(YEAR FROM icu.intime) - p.anchor_year)) BETWEEN 83 AND 93
  ),

  -- 2. Filter for patients with sepsis diagnosis during the admission corresponding to their first ICU stay
  sepsis_admissions_for_cohort AS (
    SELECT DISTINCT
      fs.subject_id,
      fs.hadm_id,
      fs.stay_id,
      fs.intime,
      fs.outtime,
      fs.hospital_expire_flag,
      fs.age_at_icu_intime
    FROM
      first_icu_stay_cohort AS fs
      JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` AS diag ON fs.hadm_id = diag.hadm_id
    WHERE
      fs.rn_icu_stay = 1 -- Ensure it's the absolute first ICU stay for the patient
      AND (
        -- ICD-9 codes for sepsis
        (diag.icd_version = 9 AND (
            diag.icd_code LIKE '038%' OR -- Septicemia
            diag.icd_code = '99591' OR -- Sepsis
            diag.icd_code = '99592'    -- Severe sepsis
        ))
        OR
        -- ICD-10 codes for sepsis
        (diag.icd_version = 10 AND (
            diag.icd_code LIKE 'A40%' OR -- Streptococcal sepsis
            diag.icd_code LIKE 'A41%' OR -- Other sepsis
            diag.icd_code LIKE 'R652%'   -- Severe sepsis/septic shock
        ))
      )
  ),

  -- 3. Gather all distinct diagnostic itemids within the first 72 hours of ICU stay
  diagnostic_events_72hr AS (
    -- Lab events
    SELECT
      sa.stay_id,
      le.itemid AS diagnostic_item_id
    FROM
      sepsis_admissions_for_cohort AS sa
      JOIN `physionet-data.mimiciv_3_1_hosp.labevents` AS le ON sa.subject_id = le.subject_id AND sa.hadm_id = le.hadm_id
    WHERE
      le.charttime BETWEEN sa.intime AND DATETIME_ADD(sa.intime, INTERVAL 72 HOUR)

    UNION ALL

    -- Chart events
    SELECT
      sa.stay_id,
      ce.itemid AS diagnostic_item_id
    FROM
      sepsis_admissions_for_cohort AS sa
      JOIN `physionet-data.mimiciv_3_1_icu.chartevents` AS ce ON sa.subject_id = ce.subject_id AND sa.stay_id = ce.stay_id
    WHERE
      ce.charttime BETWEEN sa.intime AND DATETIME_ADD(sa.intime, INTERVAL 72 HOUR)
  ),
  
  -- 4. Calculate the count of distinct diagnostic procedures for each stay
  diagnostic_intensity AS (
    SELECT
      stay_id,
      COUNT(DISTINCT diagnostic_item_id) AS distinct_diagnostic_procedures_72hr
    FROM
      diagnostic_events_72hr
    GROUP BY
      stay_id
  ),

  -- 5. Combine patient info with diagnostic intensity and calculate ICU LOS
  sepsis_cohort_with_metrics AS (
    SELECT
      sa.subject_id,
      sa.hadm_id,
      sa.stay_id,
      COALESCE(di.distinct_diagnostic_procedures_72hr, 0) AS distinct_diagnostic_procedures_72hr,
      DATETIME_DIFF(sa.outtime, sa.intime, HOUR) / 24.0 AS icu_los_days,
      sa.hospital_expire_flag AS mortality_flag
    FROM
      sepsis_admissions_for_cohort AS sa
      LEFT JOIN diagnostic_intensity AS di ON sa.stay_id = di.stay_id
  ),

  -- 6. Assign quartiles based on diagnostic intensity
  quartiled_cohort AS (
    SELECT
      *,
      NTILE(4) OVER (ORDER BY distinct_diagnostic_procedures_72hr ASC) AS diagnostic_intensity_quartile
    FROM
      sepsis_cohort_with_metrics
  )

-- 7. Report mean procedure counts, mean ICU LOS, and mortality (%) per quartile
SELECT
  diagnostic_intensity_quartile,
  COUNT(DISTINCT subject_id) AS num_patients_in_quartile,
  COUNT(DISTINCT stay_id) AS num_icu_stays_in_quartile,
  ROUND(AVG(distinct_diagnostic_procedures_72hr), 2) AS mean_distinct_procedures_72hr,
  ROUND(AVG(icu_los_days), 2) AS mean_icu_los_days,
  ROUND(AVG(mortality_flag) * 100, 2) AS mortality_percentage
FROM
  quartiled_cohort
GROUP BY
  diagnostic_intensity_quartile
ORDER BY
  diagnostic_intensity_quartile;