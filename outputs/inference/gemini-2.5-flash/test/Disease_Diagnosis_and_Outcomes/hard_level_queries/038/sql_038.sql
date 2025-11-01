WITH base_population AS (
    SELECT
        ad.subject_id,
        ad.hadm_id,
        pa.gender,
        pa.anchor_age AS age,
        ad.admittime,
        ad.dischtime,
        ad.deathtime,
        -- Calculate 30-day mortality flag
        CASE
            WHEN ad.deathtime IS NOT NULL
                 AND DATETIME_DIFF(ad.deathtime, ad.admittime, DAY) <= 30 THEN 1
            ELSE 0
        END AS thirty_day_mortality_flag,
        -- Calculate Length of Stay (in days) for all admissions
        DATETIME_DIFF(ad.dischtime, ad.admittime, HOUR) / 24.0 AS los_days,
        -- Flag for patients who survived beyond 30 days OR were discharged alive (for LOS calculation)
        CASE
            WHEN ad.deathtime IS NULL OR DATETIME_DIFF(ad.deathtime, ad.admittime, DAY) > 30 THEN 1
            ELSE 0
        END AS survivor_for_los_flag
    FROM
        `physionet-data.mimiciv_3_1_hosp.admissions` ad
    INNER JOIN
        `physionet-data.mimiciv_3_1_hosp.patients` pa
        ON ad.subject_id = pa.subject_id
    WHERE
        pa.gender = 'M'
        AND pa.anchor_age BETWEEN 74 AND 84
),
-- CTE to identify admissions with AKI (Acute Kidney Injury) diagnoses
aki_admissions AS (
    SELECT DISTINCT
        hadm_id
    FROM
        `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` di
    WHERE
        (di.icd_version = 9 AND di.icd_code LIKE '584%') -- ICD-9 codes for AKI (e.g., 584, 584.9, etc.)
        OR
        (di.icd_version = 10 AND di.icd_code LIKE 'N17%') -- ICD-10 codes for AKI (e.g., N17.0, N17.9, etc.)
),
-- CTE to identify admissions with ARDS (Acute Respiratory Distress Syndrome) diagnoses
ards_admissions AS (
    SELECT DISTINCT
        hadm_id
    FROM
        `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` di
    WHERE
        (di.icd_version = 9 AND di.icd_code = '5185') -- ICD-9 code for Acute lung injury; adult respiratory distress syndrome
        OR
        (di.icd_version = 10 AND di.icd_code = 'J80') -- ICD-10 code for Acute respiratory distress syndrome
),
-- Combine all flags into a single table for easier aggregation
admissions_with_flags AS (
    SELECT
        bp.*,
        -- Flag if this admission has an AKI diagnosis
        CASE WHEN aki.hadm_id IS NOT NULL THEN 1 ELSE 0 END AS has_aki,
        -- Flag if this admission has an ARDS diagnosis
        CASE WHEN ards.hadm_id IS NOT NULL THEN 1 ELSE 0 END AS has_ards
    FROM
        base_population bp
    LEFT JOIN
        aki_admissions aki
        ON bp.hadm_id = aki.hadm_id
    LEFT JOIN
        ards_admissions ards
        ON bp.hadm_id = ards.hadm_id
)
-- Calculate metrics for the AKI cohort (Male 74-84 with AKI)
SELECT
    'AKI Cohort (Male 74-84)' AS cohort_name,
    NULL AS median_risk_score, -- Risk score definition not provided in MIMIC-IV schema
    NULL AS iqr_risk_score,    -- Risk score definition not provided in MIMIC-IV schema
    SAFE_DIVIDE(SUM(thirty_day_mortality_flag), COUNT(hadm_id)) AS thirty_day_mortality_rate,
    SAFE_DIVIDE(SUM(has_ards), COUNT(hadm_id)) AS ards_rate,
    APPROX_QUANTILES(CASE WHEN survivor_for_los_flag = 1 THEN los_days ELSE NULL END, 4)[OFFSET(2)] AS median_survivor_los_days, -- Median LOS for survivors
    (APPROX_QUANTILES(CASE WHEN survivor_for_los_flag = 1 THEN los_days ELSE NULL END, 4)[OFFSET(3)] - APPROX_QUANTILES(CASE WHEN survivor_for_los_flag = 1 THEN los_days ELSE NULL END, 4)[OFFSET(1)]) AS iqr_survivor_los_days, -- IQR LOS for survivors
    NULL AS risk_percentile -- Risk score definition not provided in MIMIC-IV schema
FROM
    admissions_with_flags
WHERE
    has_aki = 1

UNION ALL

-- Calculate metrics for the General Cohort (Male 74-84)
SELECT
    'General Cohort (Male 74-84)' AS cohort_name,
    NULL AS median_risk_score, -- Risk score definition not provided in MIMIC-IV schema
    NULL AS iqr_risk_score,    -- Risk score definition not provided in MIMIC-IV schema
    SAFE_DIVIDE(SUM(thirty_day_mortality_flag), COUNT(hadm_id)) AS thirty_day_mortality_rate,
    SAFE_DIVIDE(SUM(has_ards), COUNT(hadm_id)) AS ards_rate,
    APPROX_QUANTILES(CASE WHEN survivor_for_los_flag = 1 THEN los_days ELSE NULL END, 4)[OFFSET(2)] AS median_survivor_los_days, -- Median LOS for survivors
    (APPROX_QUANTILES(CASE WHEN survivor_for_los_flag = 1 THEN los_days ELSE NULL END, 4)[OFFSET(3)] - APPROX_QUANTILES(CASE WHEN survivor_for_los_flag = 1 THEN los_days ELSE NULL END, 4)[OFFSET(1)]) AS iqr_survivor_los_days, -- IQR LOS for survivors
    NULL AS risk_percentile -- Risk score definition not provided in MIMIC-IV schema
FROM
    admissions_with_flags
WHERE
    TRUE -- No additional filtering for the general cohort
ORDER BY
    cohort_name;