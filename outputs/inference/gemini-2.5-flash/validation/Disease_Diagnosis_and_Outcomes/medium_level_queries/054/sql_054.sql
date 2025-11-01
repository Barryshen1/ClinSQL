WITH charlson_map AS (
    -- Example ICD-9 Codes and weights
    SELECT '410' AS icd_code_prefix, 3 AS weight, 9 AS icd_version, 'Myocardial Infarction' AS condition_name UNION ALL
    SELECT '412' AS icd_code_prefix, 1 AS weight, 9 AS icd_version, 'Congestive Heart Failure' AS condition_name UNION ALL
    SELECT '428' AS icd_code_prefix, 1 AS weight, 9 AS icd_version, 'Congestive Heart Failure' AS condition_name UNION ALL
    SELECT '430' AS icd_code_prefix, 1 AS weight, 9 AS icd_version, 'Cerebrovascular Disease' AS condition_name UNION ALL
    SELECT '431' AS icd_code_prefix, 1 AS weight, 9 AS icd_version, 'Cerebrovascular Disease' AS condition_name UNION ALL
    SELECT '432' AS icd_code_prefix, 1 AS weight, 9 AS icd_version, 'Cerebrovascular Disease' AS condition_name UNION ALL
    SELECT '433' AS icd_code_prefix, 1 AS weight, 9 AS icd_version, 'Cerebrovascular Disease' AS condition_name UNION ALL
    SELECT '434' AS icd_code_prefix, 1 AS weight, 9 AS icd_version, 'Cerebrovascular Disease' AS condition_name UNION ALL
    SELECT '435' AS icd_code_prefix, 1 AS weight, 9 AS icd_version, 'Cerebrovascular Disease' AS condition_name UNION ALL
    SELECT '436' AS icd_code_prefix, 1 AS weight, 9 AS icd_version, 'Cerebrovascular Disease' AS condition_name UNION ALL
    SELECT '437' AS icd_code_prefix, 1 AS weight, 9 AS icd_version, 'Cerebrovascular Disease' AS condition_name UNION ALL
    SELECT '440' AS icd_code_prefix, 1 AS weight, 9 AS icd_version, 'Peripheral Vascular Disease' AS condition_name UNION ALL
    SELECT '441' AS icd_code_prefix, 1 AS weight, 9 AS icd_version, 'Peripheral Vascular Disease' AS condition_name UNION ALL
    SELECT '442' AS icd_code_prefix, 1 AS weight, 9 AS icd_version, 'Peripheral Vascular Disease' AS condition_name UNION ALL
    SELECT '443' AS icd_code_prefix, 1 AS weight, 9 AS icd_version, 'Peripheral Vascular Disease' AS condition_name UNION ALL
    SELECT '447' AS icd_code_prefix, 1 AS weight, 9 AS icd_version, 'Peripheral Vascular Disease' AS condition_name UNION ALL
    SELECT '250.0' AS icd_code_prefix, 1 AS weight, 9 AS icd_version, 'Diabetes without Complications' AS condition_name UNION ALL
    SELECT '250.1' AS icd_code_prefix, 1 AS weight, 9 AS icd_version, 'Diabetes without Complications' AS condition_name UNION ALL
    SELECT '250.2' AS icd_code_prefix, 1 AS weight, 9 AS icd_version, 'Diabetes without Complications' AS condition_name UNION ALL
    SELECT '250.3' AS icd_code_prefix, 1 AS weight, 9 AS icd_version, 'Diabetes without Complications' AS condition_name UNION ALL
    SELECT '250.4' AS icd_code_prefix, 2 AS weight, 9 AS icd_version, 'Diabetes with Complications' AS condition_name UNION ALL
    SELECT '250.5' AS icd_code_prefix, 2 AS weight, 9 AS icd_version, 'Diabetes with Complications' AS condition_name UNION ALL
    SELECT '250.6' AS icd_code_prefix, 2 AS weight, 9 AS icd_version, 'Diabetes with Complications' AS condition_name UNION ALL
    SELECT '250.7' AS icd_code_prefix, 2 AS weight, 9 AS icd_version, 'Diabetes with Complications' AS condition_name UNION ALL
    SELECT '250.8' AS icd_code_prefix, 2 AS weight, 9 AS icd_version, 'Diabetes with Complications' AS condition_name UNION ALL
    SELECT '250.9' AS icd_code_prefix, 2 AS weight, 9 AS icd_version, 'Diabetes with Complications' AS condition_name UNION ALL
    -- Example ICD-10 Codes and weights
    SELECT 'I21' AS icd_code_prefix, 3 AS weight, 10 AS icd_version, 'Myocardial Infarction' AS condition_name UNION ALL
    SELECT 'I50' AS icd_code_prefix, 1 AS weight, 10 AS icd_version, 'Congestive Heart Failure' AS condition_name UNION ALL
    SELECT 'I60' AS icd_code_prefix, 1 AS weight, 10 AS icd_version, 'Cerebrovascular Disease' AS condition_name UNION ALL
    SELECT 'I61' AS icd_code_prefix, 1 AS weight, 10 AS icd_version, 'Cerebrovascular Disease' AS condition_name UNION ALL
    SELECT 'I62' AS icd_code_prefix, 1 AS weight, 10 AS icd_version, 'Cerebrovascular Disease' AS condition_name UNION ALL
    SELECT 'I63' AS icd_code_prefix, 1 AS weight, 10 AS icd_version, 'Cerebrovascular Disease' AS condition_name UNION ALL
    SELECT 'I64' AS icd_code_prefix, 1 AS weight, 10 AS icd_version, 'Cerebrovascular Disease' AS condition_name UNION ALL
    SELECT 'I65' AS icd_code_prefix, 1 AS weight, 10 AS icd_version, 'Cerebrovascular Disease' AS condition_name UNION ALL
    SELECT 'I66' AS icd_code_prefix, 1 AS weight, 10 AS icd_version, 'Cerebrovascular Disease' AS condition_name UNION ALL
    SELECT 'I67' AS icd_code_prefix, 1 AS weight, 10 AS icd_version, 'Cerebrovascular Disease' AS condition_name UNION ALL
    SELECT 'I68' AS icd_code_prefix, 1 AS weight, 10 AS icd_version, 'Cerebrovascular Disease' AS condition_name UNION ALL
    SELECT 'I69' AS icd_code_prefix, 1 AS weight, 10 AS icd_version, 'Cerebrovascular Disease' AS condition_name UNION ALL
    SELECT 'I70' AS icd_code_prefix, 1 AS weight, 10 AS icd_version, 'Peripheral Vascular Disease' AS condition_name UNION ALL
    SELECT 'I71' AS icd_code_prefix, 1 AS weight, 10 AS icd_version, 'Peripheral Vascular Disease' AS condition_name UNION ALL
    SELECT 'I72' AS icd_code_prefix, 1 AS weight, 10 AS icd_version, 'Peripheral Vascular Disease' AS condition_name UNION ALL
    SELECT 'I73' AS icd_code_prefix, 1 AS weight, 10 AS icd_version, 'Peripheral Vascular Disease' AS condition_name UNION ALL
    SELECT 'I74' AS icd_code_prefix, 1 AS weight, 10 AS icd_version, 'Peripheral Vascular Disease' AS condition_name UNION ALL
    SELECT 'I77' AS icd_code_prefix, 1 AS weight, 10 AS icd_version, 'Peripheral Vascular Disease' AS condition_name UNION ALL
    SELECT 'I79' AS icd_code_prefix, 1 AS weight, 10 AS icd_version, 'Peripheral Vascular Disease' AS condition_name UNION ALL
    SELECT 'E10' AS icd_code_prefix, 1 AS weight, 10 AS icd_version, 'Diabetes without Complications' AS condition_name UNION ALL
    SELECT 'E11' AS icd_code_prefix, 1 AS weight, 10 AS icd_version, 'Diabetes without Complications' AS condition_name UNION ALL
    SELECT 'E12' AS icd_code_prefix, 1 AS weight, 10 AS icd_version, 'Diabetes without Complications' AS condition_name UNION ALL
    SELECT 'E13' AS icd_code_prefix, 1 AS weight, 10 AS icd_version, 'Diabetes without Complications' AS condition_name UNION ALL
    SELECT 'E14' AS icd_code_prefix, 1 AS weight, 10 AS icd_version, 'Diabetes without Complications' AS condition_name UNION ALL
    SELECT 'E08' AS icd_code_prefix, 2 AS weight, 10 AS icd_version, 'Diabetes with Complications' AS condition_name UNION ALL
    SELECT 'E09' AS icd_code_prefix, 2 AS weight, 10 AS icd_version, 'Diabetes with Complications' AS condition_name UNION ALL
    SELECT 'C' AS icd_code_prefix, 2 AS weight, 10 AS icd_version, 'Cancer' AS condition_name UNION ALL -- C00-C96 malignant neoplasms, simplified to 'C'
    SELECT 'D05' AS icd_code_prefix, 2 AS weight, 10 AS icd_version, 'Cancer' AS condition_name -- Other specific cancer codes
),
charlson_comorbidities AS (
    SELECT
        di.hadm_id,
        cm.condition_name,
        MAX(cm.weight) AS condition_weight -- Take max weight if a patient has multiple codes for the same condition_name
    FROM
        `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` di
    INNER JOIN
        charlson_map cm
        ON di.icd_version = cm.icd_version
        AND STARTS_WITH(di.icd_code, cm.icd_code_prefix)
    GROUP BY
        di.hadm_id, cm.condition_name
),
charlson_scores AS (
    SELECT
        hadm_id,
        SUM(condition_weight) AS charlson_comorbidity_index
    FROM
        charlson_comorbidities
    GROUP BY
        hadm_id
),
-- Step 2: Base patient cohort and initial admission details
base_admissions AS (
    SELECT
        pat.subject_id,
        adm.hadm_id,
        adm.admittime,
        adm.dischtime,
        adm.hospital_expire_flag,
        DATETIME_DIFF(adm.dischtime, adm.admittime, DAY) AS hospital_los
    FROM
        `physionet-data.mimiciv_3_1_hosp.patients` pat
    INNER JOIN
        `physionet-data.mimiciv_3_1_hosp.admissions` adm
        ON pat.subject_id = adm.subject_id
    WHERE
        pat.gender = 'M'
        AND pat.anchor_age = 44 -- '44-year-old male'
        -- Filter for postoperative complications
        AND EXISTS (
            SELECT 1
            FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` di
            WHERE di.hadm_id = adm.hadm_id
            AND (
                  (di.icd_version = 10 AND di.icd_code LIKE 'T8%') -- ICD-10 codes for complications of procedures
                OR (di.icd_version = 9 AND di.icd_code BETWEEN '996' AND '999') -- ICD-9 codes for complications of medical/surgical care
            )
        )
),
-- Step 3: Categorize LOS
los_categorized AS (
    SELECT
        *,
        CASE
            WHEN hospital_los <= 3 THEN '<=3 days'
            WHEN hospital_los BETWEEN 4 AND 6 THEN '4-6 days'
            WHEN hospital_los BETWEEN 7 AND 10 THEN '7-10 days'
            ELSE '>10 days'
        END AS los_category
    FROM
        base_admissions
),
-- Step 4: Determine ICU vs. Non-ICU status
icu_status AS (
    SELECT
        ba.hadm_id,
        CASE WHEN icu.hadm_id IS NOT NULL THEN 'ICU' ELSE 'Non-ICU' END AS icu_admission_type
    FROM
        (SELECT DISTINCT hadm_id FROM base_admissions) ba
    LEFT JOIN
        `physionet-data.mimiciv_3_1_icu.icustays` icu
        ON ba.hadm_id = icu.hadm_id
    GROUP BY
        ba.hadm_id, CASE WHEN icu.hadm_id IS NOT NULL THEN 'ICU' ELSE 'Non-ICU' END
),
-- Step 5: Flags for Mechanical Ventilation (MV)
mv_flags AS (
    SELECT DISTINCT
        ce.hadm_id,
        1 AS has_mechanical_ventilation
    FROM
        `physionet-data.mimiciv_3_1_icu.chartevents` ce
    INNER JOIN
        `physionet-data.mimiciv_3_1_icu.d_items` di
        ON ce.itemid = di.itemid
    WHERE
        di.category = 'Ventilation'
        OR di.label LIKE '%Ventilator%'
        OR di.label LIKE '%Trach%'
        OR di.label LIKE '%Intubated%'
        OR di.label LIKE '%CPAP%'
        OR di.label LIKE '%BiPAP%'
    GROUP BY ce.hadm_id -- Ensure one flag per hadm_id
),
-- Step 6: Flags for Vasopressors
vasopressor_flags AS (
    SELECT DISTINCT
        ie.hadm_id,
        1 AS has_vasopressors
    FROM
        `physionet-data.mimiciv_3_1_icu.inputevents` ie
    INNER JOIN
        `physionet-data.mimiciv_3_1_icu.d_items` di
        ON ie.itemid = di.itemid
    WHERE
        di.label IN ('Norepinephrine', 'Dopamine', 'Epinephrine', 'Phenylephrine', 'Vasopressin') -- Common vasopressors
    GROUP BY ie.hadm_id
),
-- Step 7: Flags for Renal Replacement Therapy (RRT)
rrt_flags AS (
    SELECT DISTINCT
        ce.hadm_id,
        1 AS has_rrt
    FROM
        `physionet-data.mimiciv_3_1_icu.chartevents` ce
    INNER JOIN
        `physionet-data.mimiciv_3_1_icu.d_items` di
        ON ce.itemid = di.itemid
    WHERE
        di.label LIKE '%Dialysis%'
        OR di.label LIKE '%CRRT%'
        OR di.label LIKE '%Hemodialysis%'
    GROUP BY ce.hadm_id
),
-- Step 8: Combine all information for the final cohort
cohort_with_all_flags AS (
    SELECT
        lc.subject_id,
        lc.hadm_id,
        lc.hospital_expire_flag,
        lc.hospital_los,
        lc.los_category,
        COALESCE(cs.charlson_comorbidity_index, 0) AS charlson_comorbidity_index,
        CASE
            WHEN COALESCE(cs.charlson_comorbidity_index, 0) <= 3 THEN '<=3'
            WHEN COALESCE(cs.charlson_comorbidity_index, 0) BETWEEN 4 AND 5 THEN '4-5'
            ELSE '>5'
        END AS charlson_group,
        ist.icu_admission_type,
        COALESCE(mv.has_mechanical_ventilation, 0) AS has_mv,
        COALESCE(vp.has_vasopressors, 0) AS has_vasopressors,
        COALESCE(rrt.has_rrt, 0) AS has_rrt
    FROM
        los_categorized lc
    LEFT JOIN
        charlson_scores cs
        ON lc.hadm_id = cs.hadm_id
    LEFT JOIN
        icu_status ist
        ON lc.hadm_id = ist.hadm_id
    LEFT JOIN
        mv_flags mv
        ON lc.hadm_id = mv.hadm_id
    LEFT JOIN
        vasopressor_flags vp
        ON lc.hadm_id = vp.hadm_id
    LEFT JOIN
        rrt_flags rrt
        ON lc.hadm_id = rrt.hadm_id
),
-- Step 9: Aggregate statistics by group
summary_stats AS (
    SELECT
        icu_admission_type,
        charlson_group,
        los_category,
        COUNT(hadm_id) AS total_admissions,
        SUM(hospital_expire_flag) AS mortality_count,
        SUM(CASE WHEN hospital_expire_flag = 1 THEN 1 ELSE 0 END) * 100.0 / COUNT(hadm_id) AS mortality_percent,
        SUM(has_mv) * 100.0 / COUNT(hadm_id) AS mv_percent,
        SUM(has_vasopressors) * 100.0 / COUNT(hadm_id) AS vasopressors_percent,
        SUM(has_rrt) * 100.0 / COUNT(hadm_id) AS rrt_percent
    FROM
        cohort_with_all_flags
    GROUP BY
        icu_admission_type, charlson_group, los_category
),
-- Step 10: Calculate baseline mortality for LOS <= 3 days for differences
mortality_baselines AS (
    SELECT
        icu_admission_type,
        charlson_group,
        mortality_percent AS baseline_mortality_percent
    FROM
        summary_stats
    WHERE
        los_category = '<=3 days'
)
-- Step 11: Final report with absolute and relative differences
SELECT
    ss.icu_admission_type,
    ss.charlson_group,
    ss.los_category,
    ss.total_admissions,
    ROUND(ss.mortality_percent, 2) AS mortality_percent,
    ROUND(ss.mv_percent, 2) AS mechanical_ventilation_percent,
    ROUND(ss.vasopressors_percent, 2) AS vasopressors_percent,
    ROUND(ss.rrt_percent, 2) AS rrt_percent,
    CASE
        WHEN ss.los_category = '<=3 days' THEN NULL -- Baseline, no difference
        ELSE ROUND(ss.mortality_percent - mb.baseline_mortality_percent, 2)
    END AS mortality_absolute_difference_vs_le_3_days,
    CASE
        WHEN ss.los_category = '<=3 days' THEN NULL -- Baseline, no difference
        WHEN mb.baseline_mortality_percent = 0 THEN NULL -- Avoid division by zero, or handle as infinite difference
        ELSE ROUND((ss.mortality_percent - mb.baseline_mortality_percent) / mb.baseline_mortality_percent * 100, 2)
    END AS mortality_relative_difference_vs_le_3_days_pct
FROM
    summary_stats ss
INNER JOIN
    mortality_baselines mb
    ON ss.icu_admission_type = mb.icu_admission_type
    AND ss.charlson_group = mb.charlson_group
ORDER BY
    ss.icu_admission_type,
    ss.charlson_group,
    CASE ss.los_category -- Order LOS categories correctly
        WHEN '<=3 days' THEN 1
        WHEN '4-6 days' THEN 2
        WHEN '7-10 days' THEN 3
        ELSE 4
    END;