WITH admissions_cohort AS (
    SELECT
        adm.subject_id,
        adm.hadm_id,
        adm.admittime,
        adm.dischtime,
        adm.deathtime AS adm_deathtime,
        pat.gender,
        pat.anchor_age,
        pat.dod -- Date of death overall
    FROM
        `physionet-data.mimiciv_3_1_hosp.admissions` adm
    INNER JOIN
        `physionet-data.mimiciv_3_1_hosp.patients` pat
        ON adm.subject_id = pat.subject_id
    WHERE
        pat.gender = 'F'
        AND pat.anchor_age BETWEEN 75 AND 85
),
-- Step 2: Identify admissions with a diagnosis of COPD exacerbation
copd_exacerbation_admissions AS (
    SELECT DISTINCT
        diag.subject_id,
        diag.hadm_id
    FROM
        `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` diag
    INNER JOIN
        `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` dict
        ON diag.icd_code = dict.icd_code AND diag.icd_version = dict.icd_version
    WHERE
        -- ICD-10 codes for COPD exacerbation
        (diag.icd_version = 10 AND (diag.icd_code LIKE 'J44.1%' OR diag.icd_code LIKE 'J44.0%'))
        -- ICD-9 code for chronic bronchitis with acute exacerbation
        OR (diag.icd_version = 9 AND diag.icd_code = '49121')
),
-- Step 3: Combine base cohort with COPD exacerbation filter and calculate initial metrics
initial_cohort_metrics AS (
    SELECT
        ac.subject_id,
        ac.hadm_id,
        DATE(ac.admittime) AS admittime_date,
        ac.dischtime,
        ac.adm_deathtime,
        ac.dod,
        -- Calculate hospital length of stay in days
        DATE_DIFF(ac.dischtime, ac.admittime, DAY) AS los_days,
        -- Flag for 90-day mortality from admission date
        CASE
            WHEN ac.dod IS NOT NULL AND ac.dod <= DATE_ADD(DATE(ac.admittime), INTERVAL 90 DAY) THEN 1
            ELSE 0
        END AS dead_within_90_days_flag,
        -- Length of stay for survivors (used for median survivor LOS)
        CASE
            WHEN NOT (ac.dod IS NOT NULL AND ac.dod <= DATE_ADD(DATE(ac.admittime), INTERVAL 90 DAY)) THEN DATE_DIFF(ac.dischtime, ac.admittime, DAY)
            ELSE NULL
        END AS survivor_los_days_for_median
    FROM
        admissions_cohort ac
    INNER JOIN
        copd_exacerbation_admissions cea
        ON ac.subject_id = cea.subject_id AND ac.hadm_id = cea.hadm_id
),
-- Step 4: Calculate risk score (number of distinct diagnoses) and major complications per admission
risk_scores_and_complications AS (
    SELECT
        icm.subject_id,
        icm.hadm_id,
        icm.admittime_date,
        icm.dischtime,
        icm.adm_deathtime,
        icm.dod,
        icm.los_days,
        icm.dead_within_90_days_flag,
        icm.survivor_los_days_for_median,
        -- Risk score: Count of distinct diagnoses for the admission
        COUNT(DISTINCT diag.icd_code) AS n_diagnoses,
        -- Flag for major complications (e.g., Sepsis, AKI, PE, DVT)
        MAX(CASE
            WHEN (diag.icd_version = 10 AND (diag.icd_code LIKE 'A41%' OR diag.icd_code LIKE 'R65.2%')) -- Sepsis (ICD-10)
              OR (diag.icd_version = 10 AND diag.icd_code LIKE 'N17%')                           -- Acute Kidney Injury (ICD-10)
              OR (diag.icd_version = 10 AND diag.icd_code LIKE 'I26%')                           -- Pulmonary Embolism (ICD-10)
              OR (diag.icd_version = 10 AND diag.icd_code LIKE 'I82%')                           -- Deep Vein Thrombosis (ICD-10)
              OR (diag.icd_version = 9 AND (diag.icd_code = '99591' OR diag.icd_code = '99592')) -- Sepsis (ICD-9)
              OR (diag.icd_version = 9 AND diag.icd_code LIKE '584%')                            -- Acute Kidney Injury (ICD-9)
              OR (diag.icd_version = 9 AND diag.icd_code LIKE '4151%')                           -- Pulmonary Embolism (ICD-9)
              OR (diag.icd_version = 9 AND diag.icd_code LIKE '4534%')                           -- Deep Vein Thrombosis (ICD-9)
            THEN 1 ELSE 0
        END) AS major_complication_flag
    FROM
        initial_cohort_metrics icm
    LEFT JOIN
        `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` diag
        ON icm.subject_id = diag.subject_id AND icm.hadm_id = diag.hadm_id
    GROUP BY
        icm.subject_id, icm.hadm_id, icm.admittime_date, icm.dischtime, icm.adm_deathtime, icm.dod, icm.los_days, icm.dead_within_90_days_flag, icm.survivor_los_days_for_median
),
-- Step 5: Assign risk quartiles based on the number of diagnoses
cohort_with_quartiles AS (
    SELECT
        *,
        NTILE(4) OVER (ORDER BY n_diagnoses, hadm_id) AS risk_quartile
    FROM
        risk_scores_and_complications
)
-- Step 6: Aggregate results by risk quartile
SELECT
    CAST(risk_quartile AS STRING) AS quartile_or_overall,
    COUNT(hadm_id) AS num_admissions,
    SAFE_DIVIDE(SUM(dead_within_90_days_flag), COUNT(hadm_id)) AS mortality_90_day_rate,
    SAFE_DIVIDE(SUM(major_complication_flag), COUNT(hadm_id)) AS major_complication_rate,
    -- Use APPROX_QUANTILES for median, casting to BIGNUMERIC for robustness
    APPROX_QUANTILES(CAST(survivor_los_days_for_median AS BIGNUMERIC), 2)[OFFSET(1)] AS median_survivor_los_days
FROM
    cohort_with_quartiles
GROUP BY
    risk_quartile

UNION ALL

-- Step 7: Calculate overall metrics for the entire cohort (75-85 female with COPD exacerbation)
SELECT
    'Overall' AS quartile_or_overall,
    COUNT(hadm_id) AS num_admissions,
    SAFE_DIVIDE(SUM(dead_within_90_days_flag), COUNT(hadm_id)) AS mortality_90_day_rate,
    SAFE_DIVIDE(SUM(major_complication_flag), COUNT(hadm_id)) AS major_complication_rate,
    APPROX_QUANTILES(CAST(survivor_los_days_for_median AS BIGNUMERIC), 2)[OFFSET(1)] AS median_survivor_los_days
FROM
    cohort_with_quartiles
ORDER BY
    quartile_or_overall;