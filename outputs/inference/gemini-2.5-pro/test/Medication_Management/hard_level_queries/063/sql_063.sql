WITH
-- Step 1: Define the base cohort of 48-58 year old male inpatients with pneumonia
cohort AS (
  SELECT
    pat.subject_id,
    adm.hadm_id,
    adm.admittime,
    adm.dischtime,
    adm.hospital_expire_flag
  FROM `physionet-data.mimiciv_3_1_hosp.patients` AS pat
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` AS adm
    ON pat.subject_id = adm.subject_id
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` AS dx
    ON adm.hadm_id = dx.hadm_id
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` AS ddx
    ON dx.icd_code = ddx.icd_code AND dx.icd_version = ddx.icd_version
  WHERE
    pat.gender = 'M'
    AND pat.anchor_age BETWEEN 48 AND 58
    AND LOWER(ddx.long_title) LIKE '%pneumonia%'
  GROUP BY 1, 2, 3, 4, 5 -- Use GROUP BY to get unique admissions
),

-- Step 2: Identify medications prescribed in the first 24 hours for the cohort
meds_first_24h AS (
  SELECT
    c.hadm_id,
    pres.drug
  FROM cohort AS c
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.prescriptions` AS pres
    ON c.hadm_id = pres.hadm_id
  WHERE
    pres.starttime BETWEEN c.admittime AND DATETIME_ADD(c.admittime, INTERVAL 24 HOUR)
),

-- Step 3: Calculate medication complexity (number of unique drugs) for each patient
med_complexity AS (
  SELECT
    hadm_id,
    COUNT(DISTINCT drug) AS med_count
  FROM meds_first_24h
  GROUP BY hadm_id
),

-- Result Part 1: Medication Complexity Distribution
med_complexity_distribution AS (
  SELECT
    'Medication Complexity' AS report_section,
    'Overall Pneumonia Cohort' AS cohort_group,
    'Mean Unique Meds' AS metric,
    ROUND(AVG(med_count), 2) AS value
  FROM med_complexity
  UNION ALL
  SELECT
    'Medication Complexity' AS report_section,
    'Overall Pneumonia Cohort' AS cohort_group,
    'P25 Unique Meds' AS metric,
    CAST(APPROX_QUANTILES(med_count, 100)[OFFSET(25)] AS FLOAT64) AS value
  FROM med_complexity
  UNION ALL
  SELECT
    'Medication Complexity' AS report_section,
    'Overall Pneumonia Cohort' AS cohort_group,
    'P50 Unique Meds (Median)' AS metric,
    CAST(APPROX_QUANTILES(med_count, 100)[OFFSET(50)] AS FLOAT64) AS value
  FROM med_complexity
  UNION ALL
  SELECT
    'Medication Complexity' AS report_section,
    'Overall Pneumonia Cohort' AS cohort_group,
    'P75 Unique Meds' AS metric,
    CAST(APPROX_QUANTILES(med_count, 100)[OFFSET(75)] AS FLOAT64) AS value
  FROM med_complexity
),

-- Step 4: Create a summary table for each patient with flags and outcomes for comparison
patient_summary AS (
  SELECT
    c.hadm_id,
    DATETIME_DIFF(c.dischtime, c.admittime, DAY) AS los_days,
    c.hospital_expire_flag AS mortality_flag,
    MAX(CASE WHEN icu.stay_id IS NOT NULL THEN 1 ELSE 0 END) AS is_icu_patient,
    MAX(CASE
        WHEN LOWER(meds.drug) LIKE '%sertraline%' OR LOWER(meds.drug) LIKE '%zoloft%' THEN 1
        WHEN LOWER(meds.drug) LIKE '%citalopram%' OR LOWER(meds.drug) LIKE '%celexa%' THEN 1
        WHEN LOWER(meds.drug) LIKE '%fluoxetine%' OR LOWER(meds.drug) LIKE '%prozac%' THEN 1
        WHEN LOWER(meds.drug) LIKE '%paroxetine%' OR LOWER(meds.drug) LIKE '%paxil%' THEN 1
        WHEN LOWER(meds.drug) LIKE '%escitalopram%' OR LOWER(meds.drug) LIKE '%lexapro%' THEN 1
        WHEN LOWER(meds.drug) LIKE '%venlafaxine%' OR LOWER(meds.drug) LIKE '%effexor%' THEN 1
        WHEN LOWER(meds.drug) LIKE '%duloxetine%' OR LOWER(meds.drug) LIKE '%cymbalta%' THEN 1
        WHEN LOWER(meds.drug) LIKE '%amitriptyline%' THEN 1
        WHEN LOWER(meds.drug) LIKE '%nortriptyline%' THEN 1
        WHEN LOWER(meds.drug) LIKE '%tramadol%' THEN 1
        WHEN LOWER(meds.drug) LIKE '%fentanyl%' THEN 1
        WHEN LOWER(meds.drug) LIKE '%linezolid%' OR LOWER(meds.drug) LIKE '%zyvox%' THEN 1
        WHEN LOWER(meds.drug) LIKE '%methylene blue%' THEN 1
        ELSE 0
    END) AS has_serotonergic_risk
  FROM cohort AS c
  LEFT JOIN `physionet-data.mimiciv_3_1_icu.icustays` AS icu
    ON c.hadm_id = icu.hadm_id
  LEFT JOIN meds_first_24h AS meds
    ON c.hadm_id = meds.hadm_id
  GROUP BY 1, 2, 3
),

-- Step 5: Unpivot the data to analyze ICU and Serotonergic groups separately
unpivoted_groups AS (
  SELECT hadm_id, los_days, mortality_flag, 'ICU Patients' AS cohort_group
  FROM patient_summary
  WHERE is_icu_patient = 1 AND los_days >= 0 -- Filter for valid LOS
  UNION ALL
  SELECT hadm_id, los_days, mortality_flag, 'Serotonergic-Risk Patients' AS cohort_group
  FROM patient_summary
  WHERE has_serotonergic_risk = 1 AND los_days >= 0 -- Filter for valid LOS
),

-- Step 6: Add the P75 LOS value to each row for top-quartile calculations
group_stats_with_p75 AS (
    SELECT
        *,
        PERCENTILE_CONT(los_days, 0.75) OVER (PARTITION BY cohort_group) AS los_p75
    FROM unpivoted_groups
),

-- Result Part 2: Sub-cohort Comparison
subcohort_comparison AS (
    SELECT
        'Sub-cohort Comparison' as report_section,
        cohort_group,
        'Mean LOS (days)' AS metric,
        ROUND(AVG(los_days), 2) AS value
    FROM group_stats_with_p75
    GROUP BY cohort_group
    UNION ALL
    SELECT
        'Sub-cohort Comparison' as report_section,
        cohort_group,
        'Overall Mortality Rate' AS metric,
        ROUND(AVG(mortality_flag), 4) AS value
    FROM group_stats_with_p75
    GROUP BY cohort_group
    UNION ALL
    SELECT
        'Sub-cohort Comparison' as report_section,
        cohort_group,
        'Top-Quartile LOS (P75, days)' AS metric,
        -- Use MIN/MAX/AVG as los_p75 is constant within the group
        ROUND(MIN(los_p75), 2) AS value
    FROM group_stats_with_p75
    GROUP BY cohort_group
    UNION ALL
    SELECT
        'Sub-cohort Comparison' as report_section,
        cohort_group,
        'Mortality Rate for Top-Quartile LOS' AS metric,
        -- Calculate mortality only for patients in the top LOS quartile
        ROUND(AVG(CASE WHEN los_days >= los_p75 THEN mortality_flag ELSE NULL END), 4) AS value
    FROM group_stats_with_p75
    GROUP BY cohort_group
)

-- Final step: Combine both results into a single output table
SELECT * FROM med_complexity_distribution
UNION ALL
SELECT * FROM subcohort_comparison
ORDER BY report_section DESC, cohort_group, metric;