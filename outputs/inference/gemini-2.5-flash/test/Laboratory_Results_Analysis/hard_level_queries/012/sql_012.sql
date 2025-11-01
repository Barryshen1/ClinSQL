WITH cohort_ami AS (
    -- Define the AMI cohort: Male inpatients aged 44-54 with an AMI diagnosis
    SELECT DISTINCT
        ad.subject_id,
        ad.hadm_id,
        ad.admittime,
        ad.dischtime,
        ad.hospital_expire_flag
    FROM `physionet-data.mimiciv_3_1_hosp`.admissions ad
    JOIN `physionet-data.mimiciv_3_1_hosp`.patients p
        ON ad.subject_id = p.subject_id
    JOIN `physionet-data.mimiciv_3_1_hosp`.diagnoses_icd di
        ON ad.hadm_id = di.hadm_id
    WHERE
        p.gender = 'M'
        AND p.anchor_age BETWEEN 44 AND 54
        AND (
            (di.icd_version = 9 AND di.icd_code LIKE '410%') OR -- ICD-9 codes for AMI
            (di.icd_version = 10 AND di.icd_code LIKE 'I21%') -- ICD-10 codes for AMI
        )
),
cohort_general_inpatients AS (
    -- Define the general inpatient cohort for comparison: Male inpatients aged 44-54, any diagnosis
    SELECT DISTINCT
        ad.subject_id,
        ad.hadm_id,
        ad.admittime,
        ad.dischtime,
        ad.hospital_expire_flag
    FROM `physionet-data.mimiciv_3_1_hosp`.admissions ad
    JOIN `physionet-data.mimiciv_3_1_hosp`.patients p
        ON ad.subject_id = p.subject_id
    WHERE
        p.gender = 'M'
        AND p.anchor_age BETWEEN 44 AND 54
),
-- Filter lab events for the targeted demographic (male, 44-54)
-- This CTE is shared by both AMI and general cohorts for efficiency.
filtered_lab_events AS (
    SELECT
        le.hadm_id,
        le.itemid
    FROM `physionet-data.mimiciv_3_1_hosp`.labevents le
    JOIN `physionet-data.mimiciv_3_1_hosp`.admissions ad
        ON le.hadm_id = ad.hadm_id
    JOIN `physionet-data.mimiciv_3_1_hosp`.patients p
        ON ad.subject_id = p.subject_id
    WHERE
        p.gender = 'M'
        AND p.anchor_age BETWEEN 44 AND 54
        AND le.charttime BETWEEN ad.admittime AND DATETIME_ADD(ad.admittime, INTERVAL 72 HOUR)
        AND le.flag = 'abnormal' -- Lab result is outside the reference range
),
lis_ami AS (
    -- Calculate Lab Instability Score (LIS) for each admission in the AMI cohort
    -- LIS is defined as the count of distinct abnormal lab itemids within the first 72 hours.
    SELECT
        ca.hadm_id,
        COUNT(DISTINCT fle.itemid) AS lab_instability_score
    FROM cohort_ami ca
    LEFT JOIN filtered_lab_events fle
        ON ca.hadm_id = fle.hadm_id
    GROUP BY
        ca.hadm_id
),
lis_general AS (
    -- Calculate Lab Instability Score (LIS) for each admission in the General Inpatient cohort
    SELECT
        cg.hadm_id,
        COUNT(DISTINCT fle.itemid) AS lab_instability_score
    FROM cohort_general_inpatients cg
    LEFT JOIN filtered_lab_events fle
        ON cg.hadm_id = fle.hadm_id
    GROUP BY
        cg.hadm_id
),
ami_cohort_metrics_base AS (
    -- Prepare all necessary per-admission metrics for the AMI cohort for subsequent aggregation
    SELECT
        ca.hadm_id,
        COALESCE(lis.lab_instability_score, 0) AS lab_instability_score, -- Treat admissions with no abnormal labs as LIS = 0
        DATETIME_DIFF(ca.dischtime, ca.admittime, HOUR) / 24.0 AS los_days,
        ca.hospital_expire_flag
    FROM cohort_ami ca
    LEFT JOIN lis_ami lis
        ON ca.hadm_id = lis.hadm_id
),
ami_cohort_percentile AS (
    -- Calculate the 75th percentile of LIS for the AMI cohort
    -- This CTE ensures PERCENTILE_CONT is calculated as a standalone window function.
    SELECT
        PERCENTILE_CONT(lab_instability_score, 0.75) OVER() AS ami_75th_percentile_lis
    FROM ami_cohort_metrics_base
),
ami_cohort_summary AS (
    -- Aggregate other results for the AMI cohort
    SELECT
        COUNT(t1.hadm_id) AS ami_cohort_size, -- Count distinct hadm_id from _base
        AVG(t1.los_days) AS ami_avg_los_days, -- LOS in days
        SUM(CASE WHEN t1.hospital_expire_flag = 1 THEN 1 ELSE 0 END) * 100.0 / COUNT(t1.hadm_id) AS ami_mortality_percentage
    FROM ami_cohort_metrics_base t1
),
general_cohort_metrics_base AS (
    -- Prepare all necessary per-admission metrics for the general inpatient cohort for subsequent aggregation
    SELECT
        cg.hadm_id,
        COALESCE(lis.lab_instability_score, 0) AS lab_instability_score -- Treat admissions with no abnormal labs as LIS = 0
    FROM cohort_general_inpatients cg
    LEFT JOIN lis_general lis
        ON cg.hadm_id = lis.hadm_id
),
general_cohort_summary AS (
    -- Aggregate results for the general inpatient cohort from the base metrics
    SELECT
        COUNT(t1.hadm_id) AS general_cohort_size, -- Count distinct hadm_id from _base
        AVG(t1.lab_instability_score) AS general_inpatients_avg_lis_comparison
    FROM general_cohort_metrics_base t1
)
-- Final selection of all requested metrics by querying the aggregated CTEs
SELECT
    (SELECT ami_75th_percentile_lis FROM ami_cohort_percentile) AS ami_cohort_75th_percentile_lab_instability_score,
    (SELECT ami_cohort_size FROM ami_cohort_summary) AS ami_cohort_total_admissions,
    (SELECT ami_avg_los_days FROM ami_cohort_summary) AS ami_cohort_average_los_days,
    (SELECT ami_mortality_percentage FROM ami_cohort_summary) AS ami_cohort_mortality_percentage,
    (SELECT general_inpatients_avg_lis_comparison FROM general_cohort_summary) AS general_inpatients_average_lab_instability_score_comparison,
    (SELECT general_cohort_size FROM general_cohort_summary) AS general_inpatients_total_admissions_for_comparison;