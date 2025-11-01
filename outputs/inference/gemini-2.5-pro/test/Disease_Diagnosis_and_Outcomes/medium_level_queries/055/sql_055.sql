WITH cohort_base AS (
    -- Step 1: Identify female patients aged 71-81 with a 'complication of care' diagnosis.
    SELECT DISTINCT adm.subject_id, adm.hadm_id
    FROM `physionet-data.mimiciv_3_1_hosp.admissions` AS adm
    JOIN `physionet-data.mimiciv_3_1_hosp.patients` AS pat
      ON adm.subject_id = pat.subject_id
    JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` AS dx
      ON adm.hadm_id = dx.hadm_id
    WHERE
      pat.gender = 'F'
      AND pat.anchor_age BETWEEN 71 AND 81
      AND
      (
        -- ICD-9 codes for 'Complications of surgical and medical care, NEC'
        (dx.icd_version = 9 AND SUBSTR(dx.icd_code, 1, 3) IN ('996', '997', '998', '999'))
        -- ICD-10 codes for 'Complications of surgical and medical care'
        OR (dx.icd_version = 10 AND (SUBSTR(dx.icd_code, 1, 2) = 'T8' OR SUBSTR(dx.icd_code, 1, 1) = 'Y'))
      )
),

admissions_details AS (
    -- Step 2: Gather details for each admission: LOS, ICU status, and key interventions.
    SELECT
      cb.hadm_id,
      adm.hospital_expire_flag,
      DATETIME_DIFF(adm.dischtime, adm.admittime, DAY) AS los,
      -- Flag for any ICU stay during the hospital admission
      CASE WHEN icu.hadm_id IS NOT NULL THEN 1 ELSE 0 END AS is_icu_stay,
      -- Flags for interventions (will be 0 if not an ICU stay)
      COALESCE(mv.mech_vent_flag, 0) AS mech_vent_flag,
      COALESCE(vaso.vasopressor_flag, 0) AS vasopressor_flag,
      COALESCE(rrt.rrt_flag, 0) AS rrt_flag
    FROM cohort_base AS cb
    JOIN `physionet-data.mimiciv_3_1_hosp.admissions` AS adm
      ON cb.hadm_id = adm.hadm_id
    -- Left join to identify ICU admissions
    LEFT JOIN (SELECT DISTINCT hadm_id FROM `physionet-data.mimiciv_3_1_icu.icustays`) AS icu
      ON cb.hadm_id = icu.hadm_id
    -- Left join to flag mechanical ventilation from procedureevents
    LEFT JOIN (
      SELECT DISTINCT hadm_id, 1 AS mech_vent_flag
      FROM `physionet-data.mimiciv_3_1_icu.procedureevents`
      WHERE itemid IN (
        225792, -- Invasive Ventilation
        225794, -- Non-invasive Ventilation
        227194  -- Invasive Ventilation/Trach
      )
    ) AS mv ON cb.hadm_id = mv.hadm_id
    -- Left join to flag vasopressor use from inputevents
    LEFT JOIN (
      SELECT DISTINCT hadm_id, 1 AS vasopressor_flag
      FROM `physionet-data.mimiciv_3_1_icu.inputevents`
      WHERE itemid IN (
        221906, -- Norepinephrine
        221289, -- Epinephrine
        222315, -- Vasopressin
        221749  -- Phenylephrine
      )
    ) AS vaso ON cb.hadm_id = vaso.hadm_id
    -- Left join to flag RRT use from procedureevents
    LEFT JOIN (
      SELECT DISTINCT hadm_id, 1 AS rrt_flag
      FROM `physionet-data.mimiciv_3_1_icu.procedureevents`
      WHERE itemid IN (
        225802, -- Dialysis - CRRT
        225803, -- Dialysis - CVVHD
        225805, -- Dialysis - CVVHDF
        225809, -- Dialysis - SLED
        225441  -- Hemodialysis
      )
    ) AS rrt ON cb.hadm_id = rrt.hadm_id
    -- Ensure LOS is valid
    WHERE DATETIME_DIFF(adm.dischtime, adm.admittime, DAY) >= 0
),

admissions_with_quartiles AS (
    -- Step 3: Assign LOS quartiles to the entire cohort
    SELECT
      *,
      NTILE(4) OVER (ORDER BY los) AS los_quartile
    FROM admissions_details
),

grouped_stats AS (
    -- Step 4: Group by admission type and LOS quartile to calculate rates
    SELECT
      is_icu_stay,
      los_quartile,
      COUNT(*) AS total_admissions,
      AVG(hospital_expire_flag) AS mortality_rate,
      AVG(mech_vent_flag) AS mech_vent_rate,
      AVG(vasopressor_flag) AS vasopressor_rate,
      AVG(rrt_flag) AS rrt_rate
    FROM admissions_with_quartiles
    GROUP BY is_icu_stay, los_quartile
),

final_report AS (
    -- Step 5: Add Q1 mortality as a baseline for comparison
    SELECT
      *,
      FIRST_VALUE(mortality_rate) OVER (PARTITION BY is_icu_stay ORDER BY los_quartile) AS mortality_q1
    FROM grouped_stats
)

-- Step 6: Format the final output table with all requested metrics
SELECT
  CASE
    WHEN is_icu_stay = 1 THEN 'ICU Stay'
    ELSE 'Non-ICU Stay'
  END AS admission_type,
  los_quartile,
  total_admissions,
  ROUND(mortality_rate * 100, 2) AS in_hospital_mortality_pct,
  -- Absolute difference in mortality % points vs Q1
  CASE
    WHEN los_quartile > 1 THEN ROUND((mortality_rate - mortality_q1) * 100, 2)
    ELSE NULL
  END AS abs_mortality_diff_vs_q1,
  -- Relative difference in mortality % vs Q1
  CASE
    WHEN los_quartile > 1 THEN ROUND(SAFE_DIVIDE(mortality_rate - mortality_q1, mortality_q1) * 100, 2)
    ELSE NULL
  END AS rel_mortality_diff_vs_q1_pct,
  ROUND(mech_vent_rate * 100, 2) AS mechanical_ventilation_pct,
  ROUND(vasopressor_rate * 100, 2) AS vasopressor_pct,
  ROUND(rrt_rate * 100, 2) AS rrt_pct
FROM final_report
ORDER BY admission_type DESC, los_quartile;