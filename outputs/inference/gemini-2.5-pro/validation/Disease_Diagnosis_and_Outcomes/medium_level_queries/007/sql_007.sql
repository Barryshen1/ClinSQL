WITH
-- Step 1: Identify the base cohort of female patients aged 51-61 with a heart failure diagnosis.
cohort AS (
  SELECT DISTINCT
    adm.subject_id,
    adm.hadm_id,
    adm.admittime,
    adm.dischtime,
    adm.hospital_expire_flag
  FROM
    `physionet-data.mimiciv_3_1_hosp.admissions` AS adm
  INNER JOIN
    `physionet-data.mimiciv_3_1_hosp.patients` AS pat
    ON adm.subject_id = pat.subject_id
  INNER JOIN
    `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` AS dx
    ON adm.hadm_id = dx.hadm_id
  WHERE
    pat.gender = 'F'
    -- Calculate age at admission and filter for 51-61 years
    AND (pat.anchor_age + EXTRACT(YEAR FROM adm.admittime) - pat.anchor_year) BETWEEN 51 AND 61
    -- Filter for Heart Failure diagnoses using both ICD-9 and ICD-10 codes
    AND (
      (dx.icd_version = 9 AND dx.icd_code LIKE '428%')
      OR (dx.icd_version = 10 AND dx.icd_code LIKE 'I50%')
    )
),

-- Step 2: Calculate comorbidity burden for each admission by counting unique diagnoses.
comorbidities AS (
  SELECT
    hadm_id,
    COUNT(DISTINCT icd_code) AS dx_count
  FROM
    `physionet-data.mimiciv_3_1_hosp.diagnoses_icd`
  GROUP BY
    hadm_id
),

-- Step 3: Identify admissions that had at least one ICU stay.
icu_admissions AS (
  SELECT DISTINCT hadm_id FROM `physionet-data.mimiciv_3_1_icu.icustays`
),

-- Step 4: Identify admissions that received Mechanical Ventilation.
-- itemids from d_items: 225792 (Invasive Ventilation), 224385 (Intubation), 225448 (ET Tube Placement)
mv_admissions AS (
  SELECT DISTINCT hadm_id
  FROM `physionet-data.mimiciv_3_1_icu.procedureevents`
  WHERE itemid IN (225792, 224385, 225448)
),

-- Step 5: Identify admissions that received vasopressors.
-- itemids from d_items: 221906 (Norepinephrine), 221289 (Epinephrine), 222315 (Vasopressin),
--                       221662 (Dopamine), 221749 (Phenylephrine)
vaso_admissions AS (
  SELECT DISTINCT hadm_id
  FROM `physionet-data.mimiciv_3_1_icu.inputevents`
  WHERE itemid IN (221906, 221289, 222315, 221662, 221749)
),

-- Step 6: Identify admissions that received Renal Replacement Therapy (RRT).
rrt_admissions AS (
  SELECT DISTINCT hadm_id FROM (
    -- RRT procedures (e.g., IHD, CVVHD)
    SELECT hadm_id FROM `physionet-data.mimiciv_3_1_icu.procedureevents` WHERE itemid IN (225802, 225803, 225805)
    UNION DISTINCT
    -- RRT outputs (e.g., dialysate)
    SELECT hadm_id FROM `physionet-data.mimiciv_3_1_icu.outputevents` WHERE itemid = 226559
    UNION DISTINCT
    -- RRT inputs (e.g., CRRT filter/dialysate)
    SELECT hadm_id FROM `physionet-data.mimiciv_3_1_icu.inputevents` WHERE itemid IN (226457, 227536)
  )
),

-- Step 7: Combine cohort with all flags and create stratification groups.
stratified_cohort AS (
  SELECT
    c.hadm_id,
    c.hospital_expire_flag,
    -- ICU vs No ICU
    CASE WHEN icu.hadm_id IS NOT NULL THEN 'ICU' ELSE 'No ICU' END AS icu_group,
    -- LOS <8 vs >=8 days
    CASE WHEN DATETIME_DIFF(c.dischtime, c.admittime, DAY) < 8 THEN 'LOS < 8' ELSE 'LOS >= 8' END AS los_group,
    -- Comorbidity burden Low/Medium/High
    CASE
      WHEN COALESCE(como.dx_count, 0) < 10 THEN 'Low'
      WHEN como.dx_count BETWEEN 10 AND 19 THEN 'Medium'
      ELSE 'High'
    END AS comorbidity_group,
    -- Intervention flags
    CASE WHEN mv.hadm_id IS NOT NULL THEN 1 ELSE 0 END AS on_mv,
    CASE WHEN vaso.hadm_id IS NOT NULL THEN 1 ELSE 0 END AS on_vaso,
    CASE WHEN rrt.hadm_id IS NOT NULL THEN 1 ELSE 0 END AS on_rrt
  FROM
    cohort AS c
  LEFT JOIN comorbidities AS como ON c.hadm_id = como.hadm_id
  LEFT JOIN icu_admissions AS icu ON c.hadm_id = icu.hadm_id
  LEFT JOIN mv_admissions AS mv ON c.hadm_id = mv.hadm_id
  LEFT JOIN vaso_admissions AS vaso ON c.hadm_id = vaso.hadm_id
  LEFT JOIN rrt_admissions AS rrt ON c.hadm_id = rrt.hadm_id
),

-- Step 8: Aggregate results by stratification groups, calculating stats for ICU and No ICU cohorts side-by-side.
grouped_stats AS (
  SELECT
    los_group,
    comorbidity_group,
    -- Patient counts
    COUNTIF(icu_group = 'ICU') AS count_icu,
    COUNTIF(icu_group = 'No ICU') AS count_no_icu,
    -- In-hospital mortality rate
    AVG(IF(icu_group = 'ICU', hospital_expire_flag, NULL)) AS mortality_rate_icu,
    AVG(IF(icu_group = 'No ICU', hospital_expire_flag, NULL)) AS mortality_rate_no_icu,
    -- Intervention prevalence (these are ICU-specific, so will be 0 for the "No ICU" group)
    AVG(IF(icu_group = 'ICU', on_mv, NULL)) AS mv_prevalence_icu,
    AVG(IF(icu_group = 'ICU', on_vaso, NULL)) AS vaso_prevalence_icu,
    AVG(IF(icu_group = 'ICU', on_rrt, NULL)) AS rrt_prevalence_icu
  FROM
    stratified_cohort
  GROUP BY
    los_group,
    comorbidity_group
)

-- Final Step: Present the results and calculate absolute/relative differences in mortality.
SELECT
  los_group,
  comorbidity_group,
  -- ICU Group Metrics
  count_icu,
  mortality_rate_icu,
  mv_prevalence_icu,
  vaso_prevalence_icu,
  rrt_prevalence_icu,
  -- Non-ICU Group Metrics
  count_no_icu,
  mortality_rate_no_icu,
  -- Calculated Differences
  (mortality_rate_icu - mortality_rate_no_icu) AS absolute_mortality_difference,
  SAFE_DIVIDE((mortality_rate_icu - mortality_rate_no_icu), mortality_rate_no_icu) AS relative_mortality_difference
FROM
  grouped_stats
WHERE
  count_icu > 0 OR count_no_icu > 0 -- Exclude empty strata
ORDER BY
  los_group,
  comorbidity_group;