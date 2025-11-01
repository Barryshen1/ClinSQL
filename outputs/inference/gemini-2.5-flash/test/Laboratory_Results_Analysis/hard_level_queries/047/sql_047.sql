WITH ards_patients AS (
    -- Step 1: Define the base ARDS cohort (male, 71-81, with ARDS diagnosis)
    SELECT
        ad.subject_id,
        ad.hadm_id,
        ad.admittime,
        ad.dischtime,
        ad.hospital_expire_flag,
        -- Calculate LOS for later use, or use DATETIME_DIFF in final select
        DATETIME_DIFF(ad.dischtime, ad.admittime, HOUR) / 24.0 AS los_days
    FROM `physionet-data.mimiciv_3_1_hosp.admissions` AS ad
    INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` AS p
        ON ad.subject_id = p.subject_id
    INNER JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` AS di
        ON ad.subject_id = di.subject_id AND ad.hadm_id = di.hadm_id
    WHERE
        p.gender = 'M'
        AND p.anchor_age BETWEEN 71 AND 81
        AND di.icd_code = 'J80' -- ICD-10 code for Acute respiratory distress syndrome (ARDS)
        AND di.icd_version = 10
),
control_patients AS (
    -- Step 7: Define the control cohort (male, 71-81, WITHOUT ARDS diagnosis)
    SELECT
        ad.subject_id,
        ad.hadm_id,
        ad.admittime,
        ad.dischtime,
        ad.hospital_expire_flag,
        DATETIME_DIFF(ad.dischtime, ad.admittime, HOUR) / 24.0 AS los_days
    FROM `physionet-data.mimiciv_3_1_hosp.admissions` AS ad
    INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` AS p
        ON ad.subject_id = p.subject_id
    WHERE
        p.gender = 'M'
        AND p.anchor_age BETWEEN 71 AND 81
        AND NOT EXISTS (
            SELECT 1
            FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` AS di
            WHERE ad.subject_id = di.subject_id AND ad.hadm_id = di.hadm_id
            AND di.icd_code = 'J80' AND di.icd_version = 10
        )
),
ards_instability AS (
    -- Step 2 & 3: Calculate instability scores for each ARDS admission (count of distinct abnormal labs in first 72h)
    SELECT
        ar.subject_id,
        ar.hadm_id,
        COUNT(DISTINCT le.itemid) AS instability_score
    FROM ards_patients AS ar
    LEFT JOIN `physionet-data.mimiciv_3_1_hosp.labevents` AS le
        ON ar.subject_id = le.subject_id
        AND ar.hadm_id = le.hadm_id
        AND le.charttime BETWEEN ar.admittime AND DATETIME_ADD(ar.admittime, INTERVAL 72 HOUR)
        AND le.flag = 'abnormal' -- Use 'abnormal' flag to define critical/abnormal labs
    GROUP BY
        ar.subject_id,
        ar.hadm_id
),
control_instability AS (
    -- Step 8: Calculate instability scores for each control admission
    SELECT
        cp.subject_id,
        cp.hadm_id,
        COUNT(DISTINCT le.itemid) AS instability_score
    FROM control_patients AS cp
    LEFT JOIN `physionet-data.mimiciv_3_1_hosp.labevents` AS le
        ON cp.subject_id = le.subject_id
        AND cp.hadm_id = le.hadm_id
        AND le.charttime BETWEEN cp.admittime AND DATETIME_ADD(cp.admittime, INTERVAL 72 HOUR)
        AND le.flag = 'abnormal'
    GROUP BY
        cp.subject_id,
        cp.hadm_id
),
ards_90th_percentile AS (
    -- Step 4: Determine the 90th percentile instability score for ARDS patients
    -- FIX: Replaced PERCENTILE_CONT with APPROX_QUANTILES to resolve the error.
    SELECT
        APPROX_QUANTILES(ai.instability_score, 100)[OFFSET(90)] AS threshold_score
    FROM ards_instability AS ai
),
high_instability_ards_cohort AS (
    -- Step 5: Filter ARDS patients at/above the 90th percentile threshold
    SELECT
        ai.subject_id,
        ai.hadm_id,
        ai.instability_score,
        ap.hospital_expire_flag,
        ap.los_days -- Use pre-calculated LOS
    FROM ards_instability AS ai
    INNER JOIN ards_patients AS ap
        ON ai.subject_id = ap.subject_id AND ai.hadm_id = ap.hadm_id
    CROSS JOIN ards_90th_percentile AS ap90
    WHERE
        ai.instability_score >= ap90.threshold_score
)
-- Final SELECT statement: Report mortality, mean LOS, and compare critical lab rates
SELECT
    'High Instability ARDS Male (71-81)' AS cohort_name,
    COUNT(DISTINCT hia.hadm_id) AS num_admissions,
    -- Step 6: Mortality for high instability ARDS
    CAST(SUM(hia.hospital_expire_flag) AS FLOAT64) / COUNT(DISTINCT hia.hadm_id) AS mortality_rate,
    -- Step 6: Mean LOS for high instability ARDS
    AVG(hia.los_days) AS mean_los_days,
    -- Comparison: Mean instability score (critical lab rate) for high instability ARDS
    AVG(hia.instability_score) AS mean_distinct_abnormal_labs_72hr
FROM high_instability_ards_cohort AS hia

UNION ALL

SELECT
    'General Inpatients Male (71-81) without ARDS' AS cohort_name,
    COUNT(DISTINCT ci.hadm_id) AS num_admissions,
    -- Step 8: Mortality for control group
    CAST(SUM(cp.hospital_expire_flag) AS FLOAT64) / COUNT(DISTINCT ci.hadm_id) AS mortality_rate,
    -- Step 8: Mean LOS for control group
    AVG(cp.los_days) AS mean_los_days, -- Use pre-calculated LOS
    -- Comparison: Mean instability score (critical lab rate) for control group
    AVG(ci.instability_score) AS mean_distinct_abnormal_labs_72hr
FROM control_instability AS ci
INNER JOIN control_patients AS cp
    ON ci.subject_id = cp.subject_id AND ci.hadm_id = cp.hadm_id;