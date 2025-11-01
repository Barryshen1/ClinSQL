WITH
-- CTE 1: Define hyperkalemia risk categories for a representative set of drugs.
-- This list is an example and would typically be derived from a validated clinical drug database.
hyperkalemia_risk_drugs AS (
    -- ACE Inhibitors
    SELECT 'lisinopril' AS drug_name, 'ACE Inhibitor' AS drug_category UNION ALL
    SELECT 'enalapril', 'ACE Inhibitor' UNION ALL
    SELECT 'ramipril', 'ACE Inhibitor' UNION ALL
    -- ARBs (Angiotensin Receptor Blockers)
    SELECT 'losartan', 'ARB' UNION ALL
    SELECT 'valsartan', 'ARB' UNION ALL
    SELECT 'irbesartan', 'ARB' UNION ALL
    -- Potassium-sparing Diuretics
    SELECT 'spironolactone', 'Potassium-sparing Diuretic' UNION ALL
    SELECT 'eplerenone', 'Potassium-sparing Diuretic' UNION ALL
    SELECT 'amiloride', 'Potassium-sparing Diuretic' UNION ALL
    -- NSAIDs
    SELECT 'ibuprofen', 'NSAID' UNION ALL
    SELECT 'naproxen', 'NSAID' UNION ALL
    SELECT 'diclofenac', 'NSAID' UNION ALL
    -- Other specific drugs
    SELECT 'trimethoprim', 'Other Risk Drug' UNION ALL
    SELECT 'heparin', 'Other Risk Drug' UNION ALL
    SELECT 'digoxin', 'Other Risk Drug' -- Digitalis can cause hyperkalemia with toxicity
),
-- CTE 2: Get all relevant admissions data with LOS and patient demographics
admissions_data AS (
    SELECT
        adm.subject_id,
        adm.hadm_id,
        adm.admittime,
        adm.dischtime,
        adm.hospital_expire_flag,
        pat.gender,
        pat.anchor_age,
        DATETIME_DIFF(adm.dischtime, adm.admittime, HOUR) / 24.0 AS los_days
    FROM
        `physionet-data.mimiciv_3_1_hosp.admissions` adm
    INNER JOIN
        `physionet-data.mimiciv_3_1_hosp.patients` pat
        ON adm.subject_id = pat.subject_id
),
-- CTE 3: Identify admissions with Hyperosmolar Hyperglycemic State (HHS) diagnosis.
-- This includes searching for relevant ICD-10 and ICD-9 codes and keyword matches.
hhs_admissions AS (
    SELECT DISTINCT
        diag.subject_id,
        diag.hadm_id
    FROM
        `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` diag
    INNER JOIN
        `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` dicd
        ON diag.icd_code = dicd.icd_code AND diag.icd_version = dicd.icd_version
    WHERE
        (
            (dicd.long_title LIKE '%hyperosmolar%' OR dicd.long_title LIKE '%hyperglycemic hyperosmolar state%')
            AND dicd.long_title LIKE '%diabetes%'
        )
        OR -- Common ICD-10 codes for HHS/DKA (with hyperosmolarity component)
        (diag.icd_version = 10 AND diag.icd_code IN ('E1021', 'E1022', 'E1121', 'E1122', 'E1321', 'E1322'))
        OR -- Common ICD-9 codes for HHS/DKA (with hyperosmolarity component)
        (diag.icd_version = 9 AND diag.icd_code IN ('25020', '25021', '25030', '25031', '25032', '25033'))
),
-- CTE 4: Define the specific cohorts based on the clinical question criteria
cohort_definitions AS (
    SELECT
        ad.subject_id,
        ad.hadm_id,
        ad.admittime,
        ad.dischtime,
        ad.hospital_expire_flag,
        ad.gender,
        ad.anchor_age,
        ad.los_days,
        -- Target Cohort: Female inpatients aged 68–78 with HHS
        CASE
            WHEN ad.gender = 'F'
            AND ad.anchor_age BETWEEN 68 AND 78
            AND hhs.hadm_id IS NOT NULL
            THEN 1
            ELSE 0
        END AS is_hhs_female_age_cohort,
        -- Control Cohort: All inpatients
        1 AS is_all_inpatients_cohort
    FROM
        admissions_data ad
    LEFT JOIN
        hhs_admissions hhs
        ON ad.subject_id = hhs.subject_id AND ad.hadm_id = hhs.hadm_id
),
-- CTE 5: Get distinct medications administered within the first 72 hours of admission
medications_72hr AS (
    SELECT DISTINCT
        p.subject_id,
        p.hadm_id,
        p.drug
    FROM
        `physionet-data.mimiciv_3_1_hosp.prescriptions` p
    INNER JOIN
        cohort_definitions cd
        ON p.subject_id = cd.subject_id AND p.hadm_id = cd.hadm_id
    WHERE
        p.starttime >= cd.admittime
        AND p.starttime < DATETIME_ADD(cd.admittime, INTERVAL 72 HOUR)
        AND p.drug IS NOT NULL
),
-- CTE 6: Calculate medication complexity (count of distinct meds) per admission
med_complexity AS (
    SELECT
        m.subject_id,
        m.hadm_id,
        COUNT(DISTINCT m.drug) AS distinct_meds_72hr
    FROM
        medications_72hr m
    GROUP BY
        m.subject_id,
        m.hadm_id
),
-- CTE 7: Identify distinct hyperkalemia risk drug categories for each patient within 72 hours
patient_hyperkalemia_exposure AS (
    SELECT
        m.subject_id,
        m.hadm_id,
        COUNT(DISTINCT hrd.drug_category) AS distinct_hyperkalemia_risk_categories
    FROM
        medications_72hr m
    INNER JOIN
        -- Join using a case-insensitive fuzzy match for drug names for robustness
        hyperkalemia_risk_drugs hrd
        ON LOWER(m.drug) LIKE '%' || LOWER(hrd.drug_name) || '%'
    GROUP BY
        m.subject_id,
        m.hadm_id
),
-- CTE 8: Combine all relevant flags and metrics for each admission
admissions_with_flags AS (
    SELECT
        cd.*,
        COALESCE(mc.distinct_meds_72hr, 0) AS distinct_meds_72hr_count,
        COALESCE(phe.distinct_hyperkalemia_risk_categories, 0) AS distinct_hyperkalemia_risk_categories_count,
        -- Flag for hyperkalemia-risk drug interaction (2 or more distinct categories)
        CASE
            WHEN COALESCE(phe.distinct_hyperkalemia_risk_categories, 0) >= 2 THEN 1
            ELSE 0
        END AS has_hyperkalemia_interaction
    FROM
        cohort_definitions cd
    LEFT JOIN
        med_complexity mc
        ON cd.subject_id = mc.subject_id AND cd.hadm_id = mc.hadm_id
    LEFT JOIN
        patient_hyperkalemia_exposure phe
        ON cd.subject_id = phe.subject_id AND cd.hadm_id = phe.hadm_id
),
-- CTE 9: Calculate percentile rank for hyperkalemia risk levels (number of distinct categories)
-- This is computed *only for patients identified as having interactions* (>= 2 categories)
hyperkalemia_rank AS (
    SELECT
        subject_id,
        hadm_id,
        -- Apply PERCENT_RANK UDF on the category count to get the rank of this patient's interaction level
        PERCENT_RANK() OVER (ORDER BY distinct_hyperkalemia_risk_categories_count) AS percentile_rank_hyperkalemia_interaction
    FROM
        admissions_with_flags
    WHERE
        has_hyperkalemia_interaction = 1
),
-- CTE 10: Final aggregation for each cohort
final_metrics AS (
    -- Metrics for HHS Female Aged 68-78 Cohort
    SELECT
        'HHS Female Age 68-78 Cohort' AS cohort_name,
        COUNT(DISTINCT af.hadm_id) AS total_patients,
        -- Medication complexity distribution (25th, 50th, 75th percentiles of distinct medications)
        APPROX_QUANTILES(af.distinct_meds_72hr_count, 100)[OFFSET(25)] AS med_complexity_p25,
        APPROX_QUANTILES(af.distinct_meds_72hr_count, 100)[OFFSET(50)] AS med_complexity_p50,
        APPROX_QUANTILES(af.distinct_meds_72hr_count, 100)[OFFSET(75)] AS med_complexity_p75,
        -- median percentile rank of patients with hyperkalemia-risk drug interactions
        -- Use LEFT JOIN to ensure all patients are considered, but only ranks exist for those with interactions.
        -- If no patients have interactions, this will be NULL.
        APPROX_QUANTILES(hr.percentile_rank_hyperkalemia_interaction, 100)[OFFSET(50)] AS median_hyperkalemia_interaction_percentile_rank,
        -- Percent affected by hyperkalemia-risk drug interactions
        ROUND(AVG(af.has_hyperkalemia_interaction) * 100, 2) AS percent_affected_hyperkalemia_interaction,
        -- Top-quartile LOS
        APPROX_QUANTILES(af.los_days, 100)[OFFSET(75)] AS los_p75_days,
        -- Mortality
        ROUND(AVG(af.hospital_expire_flag) * 100, 2) AS mortality_percent
    FROM
        admissions_with_flags af
    LEFT JOIN
        hyperkalemia_rank hr
        ON af.subject_id = hr.subject_id AND af.hadm_id = hr.hadm_id
    WHERE
        af.is_hhs_female_age_cohort = 1
    GROUP BY
        1

    UNION ALL

    -- Metrics for All Inpatients Cohort
    SELECT
        'All Inpatients Cohort' AS cohort_name,
        COUNT(DISTINCT af.hadm_id) AS total_patients,
        APPROX_QUANTILES(af.distinct_meds_72hr_count, 100)[OFFSET(25)] AS med_complexity_p25,
        APPROX_QUANTILES(af.distinct_meds_72hr_count, 100)[OFFSET(50)] AS med_complexity_p50,
        APPROX_QUANTILES(af.distinct_meds_72hr_count, 100)[OFFSET(75)] AS med_complexity_p75,
        APPROX_QUANTILES(hr.percentile_rank_hyperkalemia_interaction, 100)[OFFSET(50)] AS median_hyperkalemia_interaction_percentile_rank,
        ROUND(AVG(af.has_hyperkalemia_interaction) * 100, 2) AS percent_affected_hyperkalemia_interaction,
        APPROX_QUANTILES(af.los_days, 100)[OFFSET(75)] AS los_p75_days,
        ROUND(AVG(af.hospital_expire_flag) * 100, 2) AS mortality_percent
    FROM
        admissions_with_flags af
    LEFT JOIN
        hyperkalemia_rank hr
        ON af.subject_id = hr.subject_id AND af.hadm_id = hr.hadm_id
    WHERE
        af.is_all_inpatients_cohort = 1
    GROUP BY
        1
)
SELECT * FROM final_metrics;