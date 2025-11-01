WITH PIVOT_DRG AS (
    -- Select the highest DRG severity for each admission if multiple exist.
    -- DRG severity is a 1-4 scale, higher number means higher severity.
    SELECT
        hadm_id,
        drg_severity
    FROM
        `physionet-data.mimiciv_3_1_hosp.drgcodes`
    QUALIFY ROW_NUMBER() OVER (PARTITION BY hadm_id ORDER BY drg_severity DESC, drg_code) = 1
),
ICH_ADMISSIONS AS (
    -- Identify unique admissions with Intracranial Hemorrhage diagnosis
    SELECT DISTINCT
        hadm_id
    FROM
        `physionet-data.mimiciv_3_1_hosp.diagnoses_icd`
    WHERE
        (icd_version = 10 AND (STARTS_WITH(icd_code, 'I60') OR STARTS_WITH(icd_code, 'I61') OR STARTS_WITH(icd_code, 'I62')))
        OR
        (icd_version = 9 AND (STARTS_WITH(icd_code, '430') OR STARTS_WITH(icd_code, '431') OR STARTS_WITH(icd_code, '432')))
),
COMPLICATION_ADMISSIONS AS (
    -- Identify unique admissions with common major complications for rate calculation.
    -- This definition is illustrative and can be expanded or refined based on specific clinical needs.
    SELECT DISTINCT
        hadm_id
    FROM
        `physionet-data.mimiciv_3_1_hosp.diagnoses_icd`
    WHERE
        (icd_version = 10 AND (
            STARTS_WITH(icd_code, 'A40') OR STARTS_WITH(icd_code, 'A41') OR STARTS_WITH(icd_code, 'R652') OR -- Sepsis (R65.2 for severe sepsis/septoc shock)
            STARTS_WITH(icd_code, 'N17') OR                                                                   -- Acute Kidney Injury
            STARTS_WITH(icd_code, 'J15') OR STARTS_WITH(icd_code, 'J18') OR                                    -- Pneumonia
            STARTS_WITH(icd_code, 'I26') OR STARTS_WITH(icd_code, 'I824') OR STARTS_WITH(icd_code, 'I825') OR STARTS_WITH(icd_code, 'I829') -- PE, DVT of lower extremity/other/unspec
        ))
        OR
        (icd_version = 9 AND (
            STARTS_WITH(icd_code, '038') OR STARTS_WITH(icd_code, '9959') OR                                   -- Sepsis (e.g., 995.91, 995.92)
            STARTS_WITH(icd_code, '584') OR                                                                    -- Acute Kidney Injury
            (REGEXP_CONTAINS(icd_code, r'^[0-9]+$') AND CAST(icd_code AS INT64) BETWEEN 480 AND 486) OR        -- Pneumonia (Range 480-486)
            STARTS_WITH(icd_code, '4151') OR STARTS_WITH(icd_code, '4534') OR STARTS_WITH(icd_code, '4538') OR STARTS_WITH(icd_code, '4539') -- PE, DVT of lower extremity/other/unspec
        ))
),
PATIENT_COHORTS AS (
    -- Base cohort: Female inpatients aged 44-54, enriched with relevant flags and scores
    SELECT
        adm.subject_id,
        adm.hadm_id,
        adm.admittime,
        adm.dischtime,
        adm.deathtime,
        pat.gender,
        pat.anchor_age,
        DATETIME_DIFF(adm.dischtime, adm.admittime, HOUR) / 24.0 AS los_days,
        (adm.deathtime IS NOT NULL AND DATETIME_DIFF(adm.deathtime, adm.admittime, DAY) <= 90) AS is_90_day_mort,
        (adm.deathtime IS NULL) AS is_survivor,
        PIVOT_DRG.drg_severity,
        (ICH_ADMISSIONS.hadm_id IS NOT NULL) AS has_ich,
        (COMPLICATION_ADMISSIONS.hadm_id IS NOT NULL) AS has_major_complication
    FROM
        `physionet-data.mimiciv_3_1_hosp.admissions` AS adm
    INNER JOIN
        `physionet-data.mimiciv_3_1_hosp.patients` AS pat
        ON adm.subject_id = pat.subject_id
    LEFT JOIN
        PIVOT_DRG
        ON adm.hadm_id = PIVOT_DRG.hadm_id
    LEFT JOIN
        ICH_ADMISSIONS
        ON adm.hadm_id = ICH_ADMISSIONS.hadm_id
    LEFT JOIN
        COMPLICATION_ADMISSIONS
        ON adm.hadm_id = COMPLICATION_ADMISSIONS.hadm_id
    WHERE
        pat.gender = 'F'
        AND pat.anchor_age BETWEEN 44 AND 54
),
TARGET_COHORT_SUMMARY AS (
    -- Summary for the target cohort: Female, 44-54, with Intracranial Hemorrhage
    SELECT
        'ICH Cohort (Female, 44-54)' AS cohort_name,
        COUNT(DISTINCT hadm_id) AS total_admissions,
        -- Risk Score (DRG Severity) - use APPROX_QUANTILES for median and IQR
        APPROX_QUANTILES(drg_severity, 100 IGNORE NULLS)[OFFSET(50)] AS median_drg_severity,
        APPROX_QUANTILES(drg_severity, 100 IGNORE NULLS)[OFFSET(25)] AS drg_severity_q1,
        APPROX_QUANTILES(drg_severity, 100 IGNORE NULLS)[OFFSET(75)] AS drg_severity_q3,
        -- 90-day Mortality Rate
        SAFE_DIVIDE(SUM(CASE WHEN is_90_day_mort THEN 1 END), COUNT(DISTINCT hadm_id)) AS _90_day_mortality_rate,
        -- Major Complication Rate
        SAFE_DIVIDE(SUM(CASE WHEN has_major_complication THEN 1 END), COUNT(DISTINCT hadm_id)) AS major_complication_rate,
        -- Median Survivor LOS
        -- Corrected BigQuery syntax for conditional aggregation
        APPROX_QUANTILES(CASE WHEN is_survivor THEN los_days ELSE NULL END, 100 IGNORE NULLS)[OFFSET(50)] AS median_survivor_los_days
    FROM
        PATIENT_COHORTS
    WHERE
        has_ich
),
COMPARISON_COHORT_SUMMARY AS (
    -- Summary for the broader comparison cohort: Female, 44-54, all diagnoses
    SELECT
        'Comparison Cohort (Female, 44-54, All Dx)' AS cohort_name,
        COUNT(DISTINCT hadm_id) AS total_admissions,
        -- Major Complication Rate
        SAFE_DIVIDE(SUM(CASE WHEN has_major_complication THEN 1 END), COUNT(DISTINCT hadm_id)) AS major_complication_rate,
        -- Median Survivor LOS
        -- Corrected BigQuery syntax for conditional aggregation
        APPROX_QUANTILES(CASE WHEN is_survivor THEN los_days ELSE NULL END, 100 IGNORE NULLS)[OFFSET(50)] AS median_survivor_los_days
    FROM
        PATIENT_COHORTS
    -- No filter on `has_ich` to include all relevant admissions for comparison
)
SELECT
    tcs.cohort_name,
    tcs.total_admissions AS ich_cohort_size,
    -- Risk Score (DRG Severity)
    CONCAT(
        CAST(tcs.median_drg_severity AS STRING),
        ' (IQR: ',
        CAST(tcs.drg_severity_q1 AS STRING),
        ' - ',
        CAST(tcs.drg_severity_q3 AS STRING),
        ')'
    ) AS ich_median_drg_severity_iqr,
    -- 90-day Mortality
    CONCAT(ROUND(tcs._90_day_mortality_rate * 100, 2), '%') AS ich_90_day_mortality_rate,
    -- Major Complication Rate
    CONCAT(ROUND(tcs.major_complication_rate * 100, 2), '% Compared to ', ROUND(ccs.major_complication_rate * 100, 2), '% in Matched Age/Gender Cohort') AS major_complication_rate_comparison,
    -- Median Survivor LOS
    CONCAT(ROUND(tcs.median_survivor_los_days, 1), ' days Compared to ', ROUND(ccs.median_survivor_los_days, 1), ' days in Matched Age/Gender Cohort') AS median_survivor_los_comparison,
    -- Matched Risk Percentile Explanation
    'To determine the matched risk percentile for a specific 49-year-old female inpatient, her DRG severity score would need to be obtained. This score would then be compared against the distribution of DRG severity scores within the "ICH Cohort (Female, 44-54)". The median DRG severity for this cohort is ' || CAST(tcs.median_drg_severity AS STRING) || ' with an IQR of ' || CAST(tcs.drg_severity_q1 AS STRING) || '-' || CAST(tcs.drg_severity_q3 AS STRING) || '.' AS risk_percentile_guidance
FROM
    TARGET_COHORT_SUMMARY AS tcs,
    COMPARISON_COHORT_SUMMARY AS ccs;