WITH pneumonia_admissions AS (
  -- Step 1: Identify the cohort of female patients aged 79-89 with pneumonia
  SELECT DISTINCT
    adm.subject_id,
    adm.hadm_id,
    adm.admittime,
    adm.dischtime,
    adm.hospital_expire_flag
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` AS adm
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` AS pat
    ON adm.subject_id = pat.subject_id
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` AS dx
    ON adm.hadm_id = dx.hadm_id
  WHERE
    pat.gender = 'F'
    AND pat.anchor_age BETWEEN 79 AND 89
    AND dx.icd_code IN (
      -- ICD-9 and ICD-10 codes for Community-Acquired & Aspiration Pneumonia
      '486',    -- Pneumonia, organism unspecified (ICD-9)
      '5070',   -- Pneumonitis due to inhalation of food or vomitus (ICD-9)
      'J189',   -- Pneumonia, unspecified organism (ICD-10)
      'J690'    -- Pneumonitis due to inhalation of food and vomitus (ICD-10)
    )
    AND adm.dischtime IS NOT NULL -- Ensure LOS can be calculated
),

mech_vent_adms AS (
  -- Step 2a: Flag admissions with mechanical ventilation
  SELECT DISTINCT hadm_id
  FROM `physionet-data.mimiciv_3_1_icu.chartevents`
  WHERE
    itemid = 223849 -- Ventilator Mode
    AND hadm_id IN (SELECT hadm_id FROM pneumonia_admissions)
),

vasopressor_adms AS (
  -- Step 2b: Flag admissions with vasopressor use
  SELECT DISTINCT hadm_id
  FROM `physionet-data.mimiciv_3_1_icu.inputevents`
  WHERE
    itemid IN (
      221906, -- Norepinephrine
      221289, -- Epinephrine
      222315, -- Vasopressin
      221662, -- Dopamine
      221749  -- Phenylephrine
    )
    AND hadm_id IN (SELECT hadm_id FROM pneumonia_admissions)
),

rrt_adms AS (
  -- Step 2c: Flag admissions with Renal Replacement Therapy (RRT)
  SELECT DISTINCT hadm_id
  FROM `physionet-data.mimiciv_3_1_icu.procedureevents`
  WHERE
    itemid IN (
      225802, -- Dialysis - CRRT
      225803, -- Dialysis - CVVHD
      225805, -- Dialysis - CVVHDF
      225807, -- Hemodialysis
      224149, -- HD CATH S/P Change
      225951  -- Peritoneal Dialysis
    )
    AND hadm_id IN (SELECT hadm_id FROM pneumonia_admissions)
),

day1_icu_adms AS (
  -- Step 2d: Flag admissions with an ICU stay within the first 24 hours
  SELECT DISTINCT pa.hadm_id
  FROM pneumonia_admissions AS pa
  INNER JOIN `physionet-data.mimiciv_3_1_icu.icustays` AS icu
    ON pa.hadm_id = icu.hadm_id
  WHERE
    -- ICU admission time is within 24 hours of hospital admission time
    DATETIME_DIFF(icu.intime, pa.admittime, HOUR) <= 24 AND icu.intime >= pa.admittime
),

categorized_admissions AS (
  -- Step 3: Combine cohort with flags and create stratification groups
  SELECT
    pa.hadm_id,
    pa.hospital_expire_flag,
    -- Create LOS group
    CASE
      WHEN DATETIME_DIFF(pa.dischtime, pa.admittime, DAY) <= 7 THEN '≤7 days'
      ELSE '>7 days'
    END AS los_group,
    -- Create ICU group
    CASE
      WHEN d1_icu.hadm_id IS NOT NULL THEN 'Day-1 ICU'
      ELSE 'No Day-1 ICU'
    END AS icu_group,
    -- Create binary flags for interventions
    CASE WHEN mv.hadm_id IS NOT NULL THEN 1 ELSE 0 END AS has_mech_vent,
    CASE WHEN vaso.hadm_id IS NOT NULL THEN 1 ELSE 0 END AS has_vasopressor,
    CASE WHEN rrt.hadm_id IS NOT NULL THEN 1 ELSE 0 END AS has_rrt
  FROM pneumonia_admissions AS pa
  LEFT JOIN mech_vent_adms AS mv
    ON pa.hadm_id = mv.hadm_id
  LEFT JOIN vasopressor_adms AS vaso
    ON pa.hadm_id = vaso.hadm_id
  LEFT JOIN rrt_adms AS rrt
    ON pa.hadm_id = rrt.hadm_id
  LEFT JOIN day1_icu_adms AS d1_icu
    ON pa.hadm_id = d1_icu.hadm_id
)

-- Step 4: Final aggregation and reporting
SELECT
  los_group,
  icu_group,
  COUNT(hadm_id) AS n_admissions,
  ROUND(AVG(hospital_expire_flag) * 100, 2) AS in_hospital_mortality_pct,
  ROUND(AVG(has_mech_vent) * 100, 2) AS mech_vent_prevalence_pct,
  ROUND(AVG(has_vasopressor) * 100, 2) AS vasopressor_prevalence_pct,
  ROUND(AVG(has_rrt) * 100, 2) AS rrt_prevalence_pct
FROM categorized_admissions
GROUP BY
  los_group,
  icu_group
ORDER BY
  los_group DESC,
  icu_group DESC;