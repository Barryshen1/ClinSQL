WITH diagnoses AS (
    -- Step 1: Create flags for all relevant diagnoses for each hospital admission.
    -- This is more efficient than joining the diagnoses table multiple times.
    SELECT
        hadm_id,
        MAX(CASE
            WHEN (icd_version = 9 AND icd_code LIKE '410%')
              OR (icd_version = 10 AND (icd_code LIKE 'I21%' OR icd_code LIKE 'I22%'))
            THEN 1 ELSE 0
        END) AS has_ami,
        MAX(CASE
            WHEN (icd_version = 9 AND icd_code LIKE '7855%') -- Shock (785.5x)
              OR (icd_version = 10 AND icd_code LIKE 'R57%') -- Shock (R57.x)
              OR (icd_version = 9 AND icd_code LIKE '5188%') -- Respiratory Failure (518.8x)
              OR (icd_version = 10 AND icd_code LIKE 'J96%') -- Respiratory Failure (J96.x)
            THEN 1 ELSE 0
        END) AS has_exclusion,
        MAX(CASE
            WHEN (icd_version = 9 AND icd_code LIKE '585%')
              OR (icd_version = 10 AND icd_code LIKE 'N18%')
            THEN 1 ELSE 0
        END) AS has_ckd,
        MAX(CASE
            WHEN (icd_version = 9 AND icd_code LIKE '250%')
              OR (icd_version = 10 AND (
                    icd_code LIKE 'E08%' OR icd_code LIKE 'E09%' OR
                    icd_code LIKE 'E10%' OR icd_code LIKE 'E11%' OR icd_code LIKE 'E13%'
              ))
            THEN 1 ELSE 0
        END) AS has_diabetes
    FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd`
    GROUP BY hadm_id
),
cohort_base AS (
    -- Step 2: Build the cohort of interest by joining patients, admissions,
    -- and the diagnosis flags, then applying inclusion/exclusion criteria.
    SELECT
        a.hadm_id,
        a.hospital_expire_flag,
        d.has_ckd,
        d.has_diabetes,
        DATETIME_DIFF(a.dischtime, a.admittime, DAY) AS los
    FROM `physionet-data.mimiciv_3_1_hosp.patients` AS p
    INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` AS a
        ON p.subject_id = a.subject_id
    INNER JOIN diagnoses AS d
        ON a.hadm_id = d.hadm_id
    WHERE
        p.gender = 'F'
        AND p.anchor_age BETWEEN 62 AND 72
        AND d.has_ami = 1
        AND d.has_exclusion = 0
),
group_stats AS (
    -- Step 3: Stratify the cohort by LOS and calculate key metrics for each group.
    SELECT
        CASE
            WHEN los <= 5 THEN 'LOS <= 5 Days'
            ELSE 'LOS > 5 Days'
        END AS los_group,
        COUNT(hadm_id) AS num_patients,
        AVG(hospital_expire_flag) * 100 AS mortality_rate_percent,
        AVG(has_ckd) * 100 AS ckd_prevalence_percent,
        AVG(has_diabetes) * 100 AS diabetes_prevalence_percent
    FROM cohort_base
    -- Ensure LOS is not null, which can happen for ongoing admissions.
    WHERE los IS NOT NULL
    GROUP BY los_group
)
-- Step 4: Pivot the two groups' stats into a single row for comparison
-- and calculate the absolute and relative differences in mortality.
SELECT
    -- Stats for LOS <= 5 days group
    los_lte_5.num_patients AS num_patients_los_lte_5,
    los_lte_5.mortality_rate_percent,
    los_lte_5.ckd_prevalence_percent AS ckd_prevalence_los_lte_5,
    los_lte_5.diabetes_prevalence_percent AS diabetes_prevalence_los_lte_5,

    -- Stats for LOS > 5 days group
    los_gt_5.num_patients AS num_patients_los_gt_5,
    los_gt_5.mortality_rate_percent,
    los_gt_5.ckd_prevalence_percent AS ckd_prevalence_los_gt_5,
    los_gt_5.diabetes_prevalence_percent AS diabetes_prevalence_los_gt_5,

    -- Mortality comparison metrics
    (los_gt_5.mortality_rate_percent - los_lte_5.mortality_rate_percent) AS absolute_mortality_difference_percent,
    SAFE_DIVIDE(los_gt_5.mortality_rate_percent, los_lte_5.mortality_rate_percent) AS relative_mortality_difference
FROM
    (SELECT * FROM group_stats WHERE los_group = 'LOS <= 5 Days') AS los_lte_5
CROSS JOIN
    (SELECT * FROM group_stats WHERE los_group = 'LOS > 5 Days') AS los_gt_5;