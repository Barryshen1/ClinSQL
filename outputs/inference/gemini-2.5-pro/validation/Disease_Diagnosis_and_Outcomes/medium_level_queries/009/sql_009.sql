WITH
  -- Step 1: Identify hospital admissions with a diagnosis of sepsis
  sepsis_dx AS (
    SELECT DISTINCT hadm_id
    FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd`
    WHERE
      (icd_version = 9 AND icd_code = '99591') -- Sepsis
      OR (icd_version = 10 AND icd_code LIKE 'A41%') -- Sepsis, various organisms
  ),
  -- Step 2: Identify hospital admissions with a diagnosis of septic shock
  septic_shock_dx AS (
    SELECT DISTINCT hadm_id
    FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd`
    WHERE
      (icd_version = 9 AND icd_code = '78552') -- Septic shock
      OR (icd_version = 10 AND icd_code = 'R6521') -- Severe sepsis with septic shock
  ),
  -- Step 3: Define the primary cohort of patients and select their first ICU stay
  first_icu_stays AS (
    SELECT
      p.subject_id,
      a.hadm_id,
      icu.stay_id,
      icu.intime,
      icu.los,
      a.hospital_expire_flag
    FROM `physionet-data.mimiciv_3_1_hosp.patients` AS p
    INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` AS a
      ON p.subject_id = a.subject_id
    INNER JOIN sepsis_dx
      ON a.hadm_id = sepsis_dx.hadm_id
    LEFT JOIN septic_shock_dx
      ON a.hadm_id = septic_shock_dx.hadm_id
    INNER JOIN (
      -- Select the first ICU stay for each hospital admission
      SELECT
        hadm_id,
        stay_id,
        intime,
        los,
        ROW_NUMBER() OVER (PARTITION BY hadm_id ORDER BY intime) AS rn
      FROM `physionet-data.mimiciv_3_1_icu.icustays`
    ) AS icu
      ON a.hadm_id = icu.hadm_id AND icu.rn = 1
    WHERE
      p.gender = 'M'
      AND p.anchor_age BETWEEN 53 AND 63
      AND septic_shock_dx.hadm_id IS NULL -- Exclude patients with septic shock
  ),
  -- Step 4: Identify ICU stays with mechanical ventilation on day 1
  day1_mech_vent AS (
    SELECT DISTINCT pe.stay_id
    FROM `physionet-data.mimiciv_3_1_icu.procedureevents` AS pe
    INNER JOIN first_icu_stays AS fs
      ON pe.stay_id = fs.stay_id
    WHERE
      pe.itemid IN (
        225792, -- Invasive Ventilation
        225794 -- Non-invasive Ventilation
      )
      AND pe.starttime BETWEEN fs.intime AND DATETIME_ADD(fs.intime, INTERVAL 1 DAY)
  ),
  -- Step 5: Identify ICU stays with vasopressor use on day 1
  day1_vasopressors AS (
    SELECT DISTINCT ie.stay_id
    FROM `physionet-data.mimiciv_3_1_icu.inputevents` AS ie
    INNER JOIN first_icu_stays AS fs
      ON ie.stay_id = fs.stay_id
    WHERE
      ie.itemid IN (
        221906, -- Norepinephrine
        221289, -- Epinephrine
        221749, -- Phenylephrine
        222315, -- Vasopressin
        221662, -- Dopamine
        221653 -- Dobutamine
      )
      AND ie.starttime BETWEEN fs.intime AND DATETIME_ADD(fs.intime, INTERVAL 1 DAY)
  ),
  -- Step 6: Identify ICU stays with RRT on day 1
  day1_rrt AS (
    SELECT DISTINCT pe.stay_id
    FROM `physionet-data.mimiciv_3_1_icu.procedureevents` AS pe
    INNER JOIN first_icu_stays AS fs
      ON pe.stay_id = fs.stay_id
    WHERE
      pe.itemid IN (
        225802, -- Dialysis - CRRT
        225803, -- Dialysis - CVVHD
        225805 -- Dialysis - Hemodialysis
      )
      AND pe.starttime BETWEEN fs.intime AND DATETIME_ADD(fs.intime, INTERVAL 1 DAY)
  ),
  -- Step 7: Combine cohort with intervention flags for final analysis
  final_cohort_with_flags AS (
    SELECT
      fs.stay_id,
      fs.los,
      fs.hospital_expire_flag,
      CASE WHEN mv.stay_id IS NOT NULL THEN 1 ELSE 0 END AS day1_mech_vent_flag,
      CASE WHEN vaso.stay_id IS NOT NULL THEN 1 ELSE 0 END AS day1_vasopressor_flag,
      CASE WHEN rrt.stay_id IS NOT NULL THEN 1 ELSE 0 END AS day1_rrt_flag
    FROM first_icu_stays AS fs
    LEFT JOIN day1_mech_vent AS mv
      ON fs.stay_id = mv.stay_id
    LEFT JOIN day1_vasopressors AS vaso
      ON fs.stay_id = vaso.stay_id
    LEFT JOIN day1_rrt AS rrt
      ON fs.stay_id = rrt.stay_id
  )
-- Step 8: Final aggregation and calculation of metrics
SELECT
  CASE
    WHEN fc.los < 8
    THEN 'LOS < 8 days'
    ELSE 'LOS >= 8 days'
  END AS los_group,
  COUNT(fc.stay_id) AS total_patients,
  ROUND(AVG(fc.hospital_expire_flag) * 100, 2) AS in_hospital_mortality_pct,
  ROUND(AVG(fc.day1_mech_vent_flag) * 100, 2) AS day1_mech_vent_pct,
  ROUND(AVG(fc.day1_vasopressor_flag) * 100, 2) AS day1_vasopressor_pct,
  ROUND(AVG(fc.day1_rrt_flag) * 100, 2) AS day1_rrt_pct
FROM final_cohort_with_flags AS fc
GROUP BY
  los_group
ORDER BY
  los_group;