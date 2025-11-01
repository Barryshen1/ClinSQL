WITH filtered_admissions_base AS (
    -- Step 1: Define the base population (Female, 74-84 years old)
    SELECT
        a.subject_id,
        a.hadm_id,
        a.admittime,
        a.dischtime,
        a.hospital_expire_flag,
        DATETIME_DIFF(a.dischtime, a.admittime, HOUR) / 24.0 AS los_days
    FROM
        `physionet-data.mimiciv_3_1_hosp.admissions` a
    JOIN
        `physionet-data.mimiciv_3_1_hosp.patients` p
        ON a.subject_id = p.subject_id
    WHERE
        p.gender = 'F'
        AND p.anchor_age BETWEEN 74 AND 84
),
ich_hadm_ids AS (
    -- Step 2: Identify admissions with Intracranial Hemorrhage (ICH) diagnoses
    SELECT DISTINCT hadm_id
    FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd`
    WHERE
        -- ICD-9 codes for Subarachnoid, Intracerebral, and Other Intracranial Hemorrhage
        (icd_version = 9 AND SUBSTR(icd_code, 1, 3) IN ('430', '431', '432'))
        -- ICD-10 codes for Nontraumatic Subarachnoid, Intracerebral, and Other Intracranial Hemorrhage
        OR (icd_version = 10 AND SUBSTR(icd_code, 1, 3) IN ('I60', 'I61', 'I62'))
),
cohorts_base AS (
    -- Step 3: Assign admissions to ICH or Control cohorts
    SELECT
        f.subject_id,
        f.hadm_id,
        f.admittime,
        f.dischtime,
        f.hospital_expire_flag,
        f.los_days,
        CASE
            WHEN ich.hadm_id IS NOT NULL THEN 'ICH_COHORT'
            ELSE 'CONTROL_COHORT'
        END AS cohort_type
    FROM
        filtered_admissions_base f
    LEFT JOIN
        ich_hadm_ids ich
        ON f.hadm_id = ich.hadm_id
    WHERE
        -- Ensure that only ICH patients are in the ICH_COHORT
        -- and non-ICH patients are in the CONTROL_COHORT
        -- If an admission has ICH, it shouldn't also be considered a control.
        -- This logic is implicitly handled by the LEFT JOIN and CASE,
        -- but an extra filter here would explicitly exclude ICH cases from CONTROL if needed
        -- For this query, the cohort_type correctly assigns 'ICH_COHORT' or 'CONTROL_COHORT'.
        1=1
),
cohorts_with_lab_instability AS (
    -- Step 4: Calculate distinct abnormal labs within the first 72 hours for both cohorts
    SELECT
        c.subject_id,
        c.hadm_id,
        c.admittime,
        c.dischtime,
        c.hospital_expire_flag,
        c.los_days,
        c.cohort_type,
        COUNT(DISTINCT CASE
                            WHEN le.valuenum IS NOT NULL -- Ensure a numeric value exists
                                AND le.ref_range_lower IS NOT NULL -- *** FIX: Use le.ref_range_lower instead of dli.ref_range_lower ***
                                AND le.ref_range_upper IS NOT NULL -- *** FIX: Use le.ref_range_upper instead of dli.ref_range_upper ***
                                AND (le.valuenum < le.ref_range_lower OR le.valuenum > le.ref_range_upper) -- Check for abnormality
                            THEN le.itemid -- Count distinct abnormal lab items
                            ELSE NULL
                        END) AS distinct_abnormal_labs_72hr
    FROM
        cohorts_base c
    LEFT JOIN
        `physionet-data.mimiciv_3_1_hosp.labevents` le
        ON c.subject_id = le.subject_id AND c.hadm_id = le.hadm_id
        AND le.charttime BETWEEN c.admittime AND DATETIME_ADD(c.admittime, INTERVAL 72 HOUR) -- Lab events within 72 hours
    -- *** REMOVED: JOIN `physionet-data.mimiciv_3_1_hosp.d_labitems` dli ON le.itemid = dli.itemid ***
    GROUP BY
        c.subject_id, c.hadm_id, c.admittime, c.dischtime, c.hospital_expire_flag, c.los_days, c.cohort_type
),
ich_cohort_with_quintiles AS (
    -- Step 5: Stratify the ICH cohort into quintiles
    SELECT
        *,
        NTILE(5) OVER (ORDER BY distinct_abnormal_labs_72hr ASC) AS lab_instability_quintile
    FROM
        cohorts_with_lab_instability
    WHERE
        cohort_type = 'ICH_COHORT'
),
-- Step 6: Final Output 1 - ICH Cohort Stratification by Quintile (as a CTE for UNION ALL)
ich_final_output AS (
    SELECT
        'ICH Cohort' AS group_category,
        FORMAT('Quintile %d', lab_instability_quintile) AS sub_group_label,
        COUNT(hadm_id) AS total_admissions,
        AVG(hospital_expire_flag) * 100 AS mortality_rate_percent,
        AVG(los_days) AS mean_los_days,
        MIN(distinct_abnormal_labs_72hr) AS min_distinct_abnormal_labs_72hr,
        MAX(distinct_abnormal_labs_72hr) AS max_distinct_abnormal_labs_72hr,
        CAST(NULL AS FLOAT64) AS avg_distinct_abnormal_labs_72hr_for_comparison -- Not applicable for quintile summary, cast for UNION ALL type consistency
    FROM
        ich_cohort_with_quintiles
    GROUP BY
        lab_instability_quintile
),
-- Step 7: Final Output 2 - Control Cohort Summary (as a CTE for UNION ALL)
control_final_output AS (
    SELECT
        'Control Group' AS group_category,
        'Overall Average' AS sub_group_label,
        COUNT(hadm_id) AS total_admissions,
        AVG(hospital_expire_flag) * 100 AS mortality_rate_percent,
        AVG(los_days) AS mean_los_days,
        CAST(NULL AS INT64) AS min_distinct_abnormal_labs_72hr, -- Not applicable for overall average, cast for UNION ALL type consistency
        CAST(NULL AS INT64) AS max_distinct_abnormal_labs_72hr,  -- Not applicable for overall average, cast for UNION ALL type consistency
        AVG(distinct_abnormal_labs_72hr) AS avg_distinct_abnormal_labs_72hr_for_comparison -- Average for comparison
    FROM
        cohorts_with_lab_instability
    WHERE
        cohort_type = 'CONTROL_COHORT'
    GROUP BY
        group_category, sub_group_label
)
-- Step 8: Combine results with UNION ALL
SELECT * FROM ich_final_output
UNION ALL
SELECT * FROM control_final_output
ORDER BY group_category, sub_group_label;