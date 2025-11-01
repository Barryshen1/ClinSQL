WITH icd_codes AS (
    -- ICD-9 and ICD-10 codes for intracranial hemorrhage
    SELECT '430' AS code, 9 AS version UNION ALL -- Subarachnoid hemorrhage
    SELECT '431' AS code, 9 AS version UNION ALL -- Intracerebral hemorrhage
    SELECT '432' AS code, 9 AS version UNION ALL -- Other and unspecified intracranial hemorrhage
    SELECT 'I60' AS code, 10 AS version UNION ALL -- Nontraumatic subarachnoid hemorrhage
    SELECT 'I61' AS code, 10 AS version UNION ALL -- Nontraumatic intracerebral hemorrhage
    SELECT 'I62' AS code, 10 AS version   -- Other nontraumatic intracranial hemorrhage
),
-- Identify subjects and hospital admissions that meet the age, gender, and diagnosis criteria
cohort_admissions AS (
    SELECT DISTINCT p.subject_id, adm.hadm_id
    FROM `physionet-data.mimiciv_3_1_hosp`.patients p
    JOIN `physionet-data.mimiciv_3_1_hosp`.admissions adm ON p.subject_id = adm.subject_id
    JOIN `physionet-data.mimiciv_3_1_hosp`.diagnoses_icd dicd ON adm.hadm_id = dicd.hadm_id
    JOIN icd_codes ON dicd.icd_code = icd_codes.code AND dicd.icd_version = icd_codes.version
    WHERE p.gender = 'F'
    AND p.anchor_age BETWEEN 50 AND 60
),
-- Get relevant ICU stay details for the identified cohort
cohort_icustays AS (
    SELECT
        ca.subject_id,
        ca.hadm_id,
        icu.stay_id,
        icu.intime,
        icu.outtime
    FROM cohort_admissions ca
    JOIN `physionet-data.mimiciv_3_1_icu`.icustays icu ON ca.subject_id = icu.subject_id AND ca.hadm_id = icu.hadm_id
),
-- Calculate procedure burden (distinct itemids) within the first 72 hours of ICU stay for the cohort
cohort_procedure_counts AS (
    SELECT
        cis.stay_id,
        COUNT(DISTINCT pe.itemid) AS procedure_burden_72hr
    FROM cohort_icustays cis
    LEFT JOIN `physionet-data.mimiciv_3_1_icu`.procedureevents pe
        ON cis.stay_id = pe.stay_id
        AND pe.starttime >= cis.intime
        AND pe.starttime < DATETIME_ADD(cis.intime, INTERVAL 72 HOUR)
    GROUP BY cis.stay_id
),
-- Final cohort data with all relevant metrics for individual stays/patients
cohort_final_data AS (
    SELECT
        cis.subject_id,
        cis.hadm_id,
        cis.stay_id,
        DATETIME_DIFF(cis.outtime, cis.intime, HOUR) AS icu_los_hours,
        COALESCE(cpc.procedure_burden_72hr, 0) AS procedure_burden_72hr,
        CASE WHEN adm.hospital_expire_flag = 1 THEN 1 ELSE 0 END AS in_hospital_mortality
    FROM cohort_icustays cis
    LEFT JOIN cohort_procedure_counts cpc ON cis.stay_id = cpc.stay_id
    JOIN `physionet-data.mimiciv_3_1_hosp`.admissions adm ON cis.hadm_id = adm.hadm_id
),
-- General ICU data for comparison
general_icu_final_data AS (
    SELECT
        icu.subject_id,
        icu.hadm_id,
        icu.stay_id,
        DATETIME_DIFF(icu.outtime, icu.intime, HOUR) AS icu_los_hours,
        CASE WHEN adm.hospital_expire_flag = 1 THEN 1 ELSE 0 END AS in_hospital_mortality
    FROM `physionet-data.mimiciv_3_1_icu`.icustays icu
    JOIN `physionet-data.mimiciv_3_1_hosp`.admissions adm ON icu.hadm_id = adm.hadm_id
)
-- Final SELECT statement to present the required statistics
SELECT
    'Cohort: Intracranial Hemorrhage, Female, 50-60' AS group_category,
    'Procedure Burden (distinct types first 72hr)' AS metric,
    '25th Percentile' AS statistic_type,
    APPROX_QUANTILES(procedure_burden_72hr, 100)[OFFSET(25)] AS value
FROM cohort_final_data
UNION ALL
SELECT
    'Cohort: Intracranial Hemorrhage, Female, 50-60',
    'Procedure Burden (distinct types first 72hr)',
    '50th Percentile (Median)',
    APPROX_QUANTILES(procedure_burden_72hr, 100)[OFFSET(50)] AS value
FROM cohort_final_data
UNION ALL
SELECT
    'Cohort: Intracranial Hemorrhage, Female, 50-60',
    'Procedure Burden (distinct types first 72hr)',
    '90th Percentile',
    APPROX_QUANTILES(procedure_burden_72hr, 100)[OFFSET(90)] AS value
FROM cohort_final_data
UNION ALL
SELECT
    'Cohort: Intracranial Hemorrhage, Female, 50-60',
    'ICU Length of Stay (hours)',
    '50th Percentile (Median)',
    APPROX_QUANTILES(icu_los_hours, 100)[OFFSET(50)] AS value
FROM cohort_final_data
UNION ALL
SELECT
    'Cohort: Intracranial Hemorrhage, Female, 50-60',
    'In-hospital Mortality',
    'Overall Percentage',
    AVG(in_hospital_mortality) * 100 AS value
FROM cohort_final_data
UNION ALL
SELECT
    'General ICU Population',
    'ICU Length of Stay (hours)',
    '50th Percentile (Median)',
    APPROX_QUANTILES(icu_los_hours, 100)[OFFSET(50)] AS value
FROM general_icu_final_data
UNION ALL
SELECT
    'General ICU Population',
    'In-hospital Mortality',
    'Overall Percentage',
    AVG(in_hospital_mortality) * 100 AS value
FROM general_icu_final_data
ORDER BY group_category, metric, statistic_type;