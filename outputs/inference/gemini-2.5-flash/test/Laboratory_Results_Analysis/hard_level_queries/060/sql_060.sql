WITH all_critical_lab_events AS (
    -- Calculate critical lab events within the first 48 hours for all admissions
    SELECT
        le.hadm_id,
        COUNT(DISTINCT le.labevent_id) AS critical_event_count_48h
    FROM
        `physionet-data.mimiciv_3_1_hosp.labevents` AS le
    INNER JOIN -- Use INNER JOIN to ensure we have an admittime for each lab event's hadm_id
        `physionet-data.mimiciv_3_1_hosp.admissions` AS ad
        ON le.hadm_id = ad.hadm_id
    WHERE
        le.charttime BETWEEN ad.admittime AND DATETIME_ADD(ad.admittime, INTERVAL 48 HOUR)
        AND le.flag = 'abnormal' -- Defining "critical" as flagged abnormal lab results
    GROUP BY
        le.hadm_id
),
cohort_admissions AS (
    -- Identify the specific cohort: 52-62 F, post-cardiac arrest
    SELECT
        ad.subject_id,
        ad.hadm_id,
        ad.admittime,
        ad.dischtime,
        ad.hospital_expire_flag
    FROM
        `physionet-data.mimiciv_3_1_hosp.admissions` AS ad
    JOIN
        `physionet-data.mimiciv_3_1_hosp.patients` AS p
        ON ad.subject_id = p.subject_id
    JOIN
        `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` AS diag
        ON ad.hadm_id = diag.hadm_id
    WHERE
        p.gender = 'F'
        AND p.anchor_age BETWEEN 52 AND 62
        AND (
            -- ICD-9 code for Cardiac arrest
            (diag.icd_version = 9 AND diag.icd_code = '4275')
            OR
            -- ICD-10 codes for Cardiac arrest
            (diag.icd_version = 10 AND diag.icd_code IN ('I462', 'I468', 'I469'))
        )
    GROUP BY -- Deduplicate admissions in case of multiple relevant diagnoses
        ad.subject_id, ad.hadm_id, ad.admittime, ad.dischtime, ad.hospital_expire_flag
),
cohort_data AS (
    -- Prepare data for the specific cohort including instability score, LOS, and mortality flag
    SELECT
        ca.subject_id,
        ca.hadm_id,
        COALESCE(acle.critical_event_count_48h, 0) AS instability_score, -- Assign 0 if no critical labs found
        DATETIME_DIFF(ca.dischtime, ca.admittime, HOUR) AS los_hours,
        ca.hospital_expire_flag
    FROM
        cohort_admissions AS ca
    LEFT JOIN
        all_critical_lab_events AS acle
        ON ca.hadm_id = acle.hadm_id
),
general_data AS (
    -- Prepare data for all general inpatients including instability score, LOS, and mortality flag
    SELECT
        ad.subject_id,
        ad.hadm_id,
        COALESCE(acle.critical_event_count_48h, 0) AS instability_score,
        DATETIME_DIFF(ad.dischtime, ad.admittime, HOUR) AS los_hours,
        ad.hospital_expire_flag
    FROM
        `physionet-data.mimiciv_3_1_hosp.admissions` AS ad
    LEFT JOIN
        all_critical_lab_events AS acle
        ON ad.hadm_id = acle.hadm_id
)
-- First part: Aggregate summary for the specific cohort
SELECT
    'Cohort: 52-62 F, Post-Cardiac arrest' AS group_name,
    APPROX_QUANTILES(cd.instability_score, 4)[OFFSET(1)] AS instability_score_q1, -- Q1 for instability score
    APPROX_QUANTILES(cd.instability_score, 4)[OFFSET(2)] AS instability_score_median, -- Median for instability score
    CAST(APPROX_QUANTILES(cd.los_hours, 2)[OFFSET(1)] AS FLOAT64) AS median_los_hours,
    (SUM(cd.hospital_expire_flag) * 100.0 / COUNT(cd.hadm_id)) AS mortality_percentage
FROM
    cohort_data AS cd
GROUP BY
    group_name

UNION ALL

-- Second part: Aggregate summary for general inpatients
SELECT
    'General Inpatients' AS group_name,
    APPROX_QUANTILES(gd.instability_score, 4)[OFFSET(1)] AS instability_score_q1, -- Q1 for instability score
    APPROX_QUANTILES(gd.instability_score, 4)[OFFSET(2)] AS instability_score_median, -- Median for instability score
    CAST(APPROX_QUANTILES(gd.los_hours, 2)[OFFSET(1)] AS FLOAT64) AS median_los_hours,
    (SUM(gd.hospital_expire_flag) * 100.0 / COUNT(gd.hadm_id)) AS mortality_percentage
FROM
    general_data AS gd
GROUP BY
    group_name;