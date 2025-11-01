WITH cohort_admissions AS (
    SELECT DISTINCT
        adm.subject_id,
        adm.hadm_id,
        adm.admittime,
        adm.dischtime,
        adm.deathtime,
        adm.hospital_expire_flag
    FROM `physionet-data.mimiciv_3_1_hosp.admissions` adm
    INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` pat
        ON adm.subject_id = pat.subject_id
    WHERE
        pat.gender = 'F'
        AND pat.anchor_age BETWEEN 55 AND 65
),
-- Step 2: Extract lab results within the first 48 hours for the cohort.
-- Filters charttime to be within 48 hours of admittime.
-- Ensures valuenum, ref_range_lower, and ref_range_upper are not NULL for valid comparisons.
early_lab_results AS (
    SELECT
        ca.subject_id,
        ca.hadm_id,
        le.labevent_id,
        le.charttime,
        le.valuenum,
        le.ref_range_lower, -- Corrected: these columns are in labevents, not d_labitems
        le.ref_range_upper, -- Corrected: these columns are in labevents, not d_labitems
        le.flag
    FROM cohort_admissions ca
    INNER JOIN `physionet-data.mimiciv_3_1_hosp.labevents` le
        ON ca.subject_id = le.subject_id AND ca.hadm_id = le.hadm_id
    WHERE
        le.charttime BETWEEN ca.admittime AND DATETIME_ADD(ca.admittime, INTERVAL 48 HOUR)
        AND le.valuenum IS NOT NULL
        AND le.ref_range_lower IS NOT NULL -- Corrected to le.
        AND le.ref_range_upper IS NOT NULL -- Corrected to le.
),
-- Step 3: Calculate the lab instability score and identify true critical labs.
-- Groups by subject_id and hadm_id.
-- lab_instability_score: Counts the number of lab results where valuenum is outside the ref_range_lower and ref_range_upper.
-- had_critical_lab_48hr: Checks if any lab event within the first 48 hours was flagged as 'CRITICAL'.
lab_instability_and_critical AS (
    SELECT
        ca.subject_id,
        ca.hadm_id,
        COUNTIF(elr.valuenum < elr.ref_range_lower OR elr.valuenum > elr.ref_range_upper) AS lab_instability_score,
        MAX(CASE WHEN elr.flag = 'CRITICAL' THEN 1 ELSE 0 END) AS had_critical_lab_48hr
    FROM cohort_admissions ca
    LEFT JOIN early_lab_results elr
        ON ca.subject_id = elr.subject_id AND ca.hadm_id = elr.hadm_id
    GROUP BY
        ca.subject_id,
        ca.hadm_id
),
-- Step 4: Combines the calculated lab scores/flags with the admission details and determines the 95th percentile of the lab instability score.
-- Performs a LEFT JOIN from cohort_admissions to lab_instability_and_critical to include patients who might have no lab data in the first 48h (their score will be 0 due to COALESCE).
-- PERCENTILE_CONT(0.95) calculates the 95th percentile across all lab instability scores in the cohort.
scores_with_percentile AS (
    SELECT
        ca.subject_id,
        ca.hadm_id,
        ca.admittime,
        ca.dischtime,
        ca.deathtime,
        ca.hospital_expire_flag,
        COALESCE(lis.lab_instability_score, 0) AS lab_instability_score,
        COALESCE(lis.had_critical_lab_48hr, 0) AS had_critical_lab_48hr,
        DATETIME_DIFF(ca.dischtime, ca.admittime, HOUR) / 24.0 AS los_days,
        PERCENTILE_CONT(0.95) OVER () AS percentile_95th_score_threshold
    FROM cohort_admissions ca
    LEFT JOIN lab_instability_and_critical lis
        ON ca.subject_id = lis.subject_id AND ca.hadm_id = lis.hadm_id
)
-- Step 5 & 6: Aggregates the results for "All Cohort" and "Top Tier" separately.
-- Calculates average LOS, mortality rate, and critical lab rate within 48 hours for each group.
-- Uses UNION ALL to present results for both groups.
SELECT
    'All Cohort (Female 55-65)' AS group_name,
    COUNT(DISTINCT hadm_id) AS num_admissions,
    ROUND(AVG(los_days), 2) AS avg_los_days,
    ROUND(AVG(hospital_expire_flag) * 100, 2) AS mortality_rate_percent,
    ROUND(AVG(had_critical_lab_48hr) * 100, 2) AS critical_lab_rate_48hr_percent
FROM scores_with_percentile
GROUP BY group_name

UNION ALL

SELECT
    'Top Tier (95th Pctile Lab Instability)' AS group_name,
    COUNT(DISTINCT hadm_id) AS num_admissions,
    ROUND(AVG(los_days), 2) AS avg_los_days,
    ROUND(AVG(hospital_expire_flag) * 100, 2) AS mortality_rate_percent,
    ROUND(AVG(had_critical_lab_48hr) * 100, 2) AS critical_lab_rate_48hr_percent
FROM scores_with_percentile
WHERE lab_instability_score >= percentile_95th_score_threshold
GROUP BY group_name;