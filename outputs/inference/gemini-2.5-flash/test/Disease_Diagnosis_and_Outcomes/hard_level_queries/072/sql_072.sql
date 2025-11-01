WITH AdmissionsFiltered AS (
    -- Base population: Female inpatients, 67-77 years old
    SELECT
        adm.subject_id,
        adm.hadm_id,
        adm.admittime,
        adm.dischtime,
        adm.hospital_expire_flag,
        pat.gender,
        pat.anchor_age, -- Using anchor_age as proxy for age at admission, as commonly done in MIMIC-IV analyses
        pat.dod,
        -- Calculate Length of Stay in days
        TIMESTAMP_DIFF(adm.dischtime, adm.admittime, HOUR) / 24.0 AS los_days
    FROM
        `physionet-data.mimiciv_3_1_hosp.admissions` AS adm
    INNER JOIN
        `physionet-data.mimiciv_3_1_hosp.patients` AS pat
        ON adm.subject_id = pat.subject_id
    WHERE
        pat.gender = 'F'
        AND pat.anchor_age BETWEEN 67 AND 77
),
IcuStaysForAdmissions AS (
    -- Collect all hadm_ids that had an ICU stay
    SELECT DISTINCT hadm_id FROM `physionet-data.mimiciv_3_1_icu.icustays`
),
CardiacComplicationDiagnoses AS (
    -- Identify admissions with specific cardiac complication ICD-10 codes
    SELECT DISTINCT hadm_id
    FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd`
    WHERE
        icd_version = 10
        AND (
            icd_code LIKE 'I44%' OR icd_code LIKE 'I45%' OR icd_code LIKE 'I46%' OR icd_code LIKE 'I47%' OR icd_code LIKE 'I48%' OR icd_code LIKE 'I49%' OR icd_code LIKE 'I50%'
        )
),
NeuroComplicationDiagnoses AS (
    -- Identify admissions with specific neurologic complication ICD-10 codes
    SELECT DISTINCT hadm_id
    FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd`
    WHERE
        icd_version = 10
        AND (
            icd_code LIKE 'I60%' OR icd_code LIKE 'I61%' OR icd_code LIKE 'I62%' OR icd_code LIKE 'I63%' OR icd_code LIKE 'I64%' OR icd_code LIKE 'I65%' OR icd_code LIKE 'I66%' OR icd_code LIKE 'I67%' OR icd_code LIKE 'I68%' OR icd_code LIKE 'I69%' -- Cerebrovascular diseases (stroke, etc.)
            OR icd_code LIKE 'G934%' -- G93.4 Encephalopathy, unspecified
            OR icd_code LIKE 'R402%' -- R40.2 Coma, unspecified
            OR icd_code LIKE 'F05%' -- F05 Delirium, not induced by alcohol and other psychoactive substances
        )
),
-- Define the Acute Coronary Syndrome (ACS) cohort:
-- Female, 67-77, ACS diagnosis, and an ICU stay
ACS_Cohort_Base AS (
    SELECT
        af.subject_id,
        af.hadm_id,
        af.admittime,
        af.dischtime,
        af.hospital_expire_flag,
        af.dod,
        af.los_days
    FROM
        AdmissionsFiltered AS af
    INNER JOIN
        `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` AS diag_acs
        ON af.hadm_id = diag_acs.hadm_id
    INNER JOIN
        IcuStaysForAdmissions AS icu
        ON af.hadm_id = icu.hadm_id
    WHERE
        diag_acs.icd_version = 10
        AND (diag_acs.icd_code LIKE 'I20%' OR diag_acs.icd_code LIKE 'I21%' OR diag_acs.icd_code LIKE 'I22%' OR diag_acs.icd_code LIKE 'I23%' OR diag_acs.icd_code LIKE 'I24%' OR diag_acs.icd_code LIKE 'I25%')
    GROUP BY -- Group by all selected columns to ensure unique admissions in the cohort
        af.subject_id, af.hadm_id, af.admittime, af.dischtime, af.hospital_expire_flag, af.dod, af.los_days
),
-- Define the General inpatient cohort:
-- All female inpatients, 67-77 (no specific diagnosis or ICU stay required)
General_Cohort_Base AS (
    SELECT
        af.subject_id,
        af.hadm_id,
        af.admittime,
        af.dischtime,
        af.hospital_expire_flag,
        af.dod,
        af.los_days
    FROM
        AdmissionsFiltered AS af
    GROUP BY -- Group by all selected columns to ensure unique admissions in the cohort
        af.subject_id, af.hadm_id, af.admittime, af.dischtime, af.hospital_expire_flag, af.dod, af.los_days
),
-- Calculate summary metrics for the ACS cohort
ACS_Summary AS (
    SELECT
        'ACS Patients with ICU Stay (Female, 67-77)' AS cohort_name,
        CAST(COUNT(DISTINCT acs.hadm_id) AS NUMERIC) AS num_admissions,
        CAST(COUNT(DISTINCT acs.subject_id) AS NUMERIC) AS num_patients,
        -- Mean DRG severity score as a proxy for 'risk score'
        AVG(drg.drg_severity) AS mean_drg_severity_score,
        -- 30-day mortality count and percentage
        CAST(SUM(CASE WHEN acs.dod IS NOT NULL AND DATE_DIFF(DATE(acs.dod), DATE(acs.admittime), DAY) <= 30 THEN 1 ELSE 0 END) AS NUMERIC) AS deaths_30_day,
        (CAST(SUM(CASE WHEN acs.dod IS NOT NULL AND DATE_DIFF(DATE(acs.dod), DATE(acs.admittime), DAY) <= 30 THEN 1 ELSE 0 END) AS NUMERIC) * 100.0) / CAST(COUNT(DISTINCT acs.hadm_id) AS NUMERIC) AS mortality_30_day_percent,
        -- Mean LOS for hospital survivors
        AVG(CASE WHEN acs.hospital_expire_flag = 0 THEN acs.los_days ELSE NULL END) AS mean_los_survivors,
        -- Cardiac complication rate
        (CAST(SUM(CASE WHEN ccd.hadm_id IS NOT NULL THEN 1 ELSE 0 END) AS NUMERIC) * 100.0) / CAST(COUNT(DISTINCT acs.hadm_id) AS NUMERIC) AS cardiac_complication_rate_percent,
        -- Neurologic complication rate
        (CAST(SUM(CASE WHEN ncd.hadm_id IS NOT NULL THEN 1 ELSE 0 END) AS NUMERIC) * 100.0) / CAST(COUNT(DISTINCT acs.hadm_id) AS NUMERIC) AS neuro_complication_rate_percent
    FROM
        ACS_Cohort_Base AS acs
    LEFT JOIN
        `physionet-data.mimiciv_3_1_hosp.drgcodes` AS drg
        ON acs.hadm_id = drg.hadm_id AND drg.drg_type = 'MS' -- Filtering for MS-DRG (Medicare Severity-DRG)
    LEFT JOIN
        CardiacComplicationDiagnoses AS ccd
        ON acs.hadm_id = ccd.hadm_id
    LEFT JOIN
        NeuroComplicationDiagnoses AS ncd
        ON acs.hadm_id = ncd.hadm_id
),
-- Calculate summary metrics for the General inpatient cohort
General_Summary AS (
    SELECT
        'General Inpatients (Female, 67-77)' AS cohort_name,
        CAST(COUNT(DISTINCT gc.hadm_id) AS NUMERIC) AS num_admissions,
        CAST(COUNT(DISTINCT gc.subject_id) AS NUMERIC) AS num_patients,
        AVG(drg.drg_severity) AS mean_drg_severity_score,
        CAST(SUM(CASE WHEN gc.dod IS NOT NULL AND DATE_DIFF(DATE(gc.dod), DATE(gc.admittime), DAY) <= 30 THEN 1 ELSE 0 END) AS NUMERIC) AS deaths_30_day,
        (CAST(SUM(CASE WHEN gc.dod IS NOT NULL AND DATE_DIFF(DATE(gc.dod), DATE(gc.admittime), DAY) <= 30 THEN 1 ELSE 0 END) AS NUMERIC) * 100.0) / CAST(COUNT(DISTINCT gc.hadm_id) AS NUMERIC) AS mortality_30_day_percent,
        AVG(CASE WHEN gc.hospital_expire_flag = 0 THEN gc.los_days ELSE NULL END) AS mean_los_survivors,
        (CAST(SUM(CASE WHEN ccd.hadm_id IS NOT NULL THEN 1 ELSE 0 END) AS NUMERIC) * 100.0) / CAST(COUNT(DISTINCT gc.hadm_id) AS NUMERIC) AS cardiac_complication_rate_percent,
        (CAST(SUM(CASE WHEN ncd.hadm_id IS NOT NULL THEN 1 ELSE 0 END) AS NUMERIC) * 100.0) / CAST(COUNT(DISTINCT gc.hadm_id) AS NUMERIC) AS neuro_complication_rate_percent
    FROM
        General_Cohort_Base AS gc
    LEFT JOIN
        `physionet-data.mimiciv_3_1_hosp.drgcodes` AS drg
        ON gc.hadm_id = drg.hadm_id AND drg.drg_type = 'MS'
    LEFT JOIN
        CardiacComplicationDiagnoses AS ccd
        ON gc.hadm_id = ccd.hadm_id
    LEFT JOIN
        NeuroComplicationDiagnoses AS ncd
        ON gc.hadm_id = ncd.hadm_id
)
-- Combine results and calculate "matched-profile percentile" (as ratio/percentage vs general group)
SELECT
    acs_sum.cohort_name,
    acs_sum.num_admissions,
    acs_sum.num_patients,
    acs_sum.mean_drg_severity_score,
    acs_sum.mortality_30_day_percent,
    acs_sum.mean_los_survivors,
    acs_sum.cardiac_complication_rate_percent,
    acs_sum.neuro_complication_rate_percent,
    -- Comparisons to General Inpatients (as percentage ratios)
    ROUND(acs_sum.mean_drg_severity_score / gs_sum.mean_drg_severity_score * 100, 2) AS drg_severity_vs_general_ratio_percent,
    ROUND(acs_sum.mortality_30_day_percent / gs_sum.mortality_30_day_percent * 100, 2) AS mortality_30_day_vs_general_ratio_percent,
    ROUND(acs_sum.mean_los_survivors / gs_sum.mean_los_survivors * 100, 2) AS los_vs_general_ratio_percent,
    ROUND(acs_sum.cardiac_complication_rate_percent / gs_sum.cardiac_complication_rate_percent * 100, 2) AS cardiac_complication_vs_general_ratio_percent,
    ROUND(acs_sum.neuro_complication_rate_percent / gs_sum.neuro_complication_rate_percent * 100, 2) AS neuro_complication_vs_general_ratio_percent
FROM
    ACS_Summary AS acs_sum
CROSS JOIN -- Use CROSS JOIN as General_Summary is a single-row aggregate table
    General_Summary AS gs_sum

UNION ALL

-- Also include the General Inpatients' metrics in a separate row for direct comparison
SELECT
    gs_sum.cohort_name,
    gs_sum.num_admissions,
    gs_sum.num_patients,
    gs_sum.mean_drg_severity_score,
    gs_sum.mortality_30_day_percent,
    gs_sum.mean_los_survivors,
    gs_sum.cardiac_complication_rate_percent,
    gs_sum.neuro_complication_rate_percent,
    -- Comparison columns are NULL for the baseline general group
    NULL AS drg_severity_vs_general_ratio_percent,
    NULL AS mortality_30_day_vs_general_ratio_percent,
    NULL AS los_vs_general_ratio_percent,
    NULL AS cardiac_complication_vs_general_ratio_percent,
    NULL AS neuro_complication_vs_general_ratio_percent
FROM
    General_Summary AS gs_sum
ORDER BY cohort_name DESC; -- Order to have ACS summary first.;