WITH
-- CTE 1: Identify eligible female patients within the age range with PE diagnosis
FemalePEPatients AS (
    SELECT DISTINCT
        adm.subject_id,
        adm.hadm_id,
        adm.admittime,
        adm.dischtime,
        adm.hospital_expire_flag
    FROM
        `physionet-data.mimiciv_3_1_hosp.patients` pat
    INNER JOIN
        `physionet-data.mimiciv_3_1_hosp.admissions` adm
        ON pat.subject_id = adm.subject_id
    INNER JOIN
        `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` di
        ON adm.subject_id = di.subject_id AND adm.hadm_id = di.hadm_id
    WHERE
        pat.gender = 'F'
        AND pat.anchor_age BETWEEN 53 AND 63
        AND (
            -- ICD-9 codes for Pulmonary Embolism (Pulmonary embolism and infarction)
            (di.icd_code LIKE '4151%' AND di.icd_version = 9)
            OR
            -- ICD-10 codes for Pulmonary Embolism
            (di.icd_code LIKE 'I26%' AND di.icd_version = 10)
        )
),
-- CTE 2: Retrieve lab data for the identified cohort within the first 72 hours of admission
LabsForCohort AS (
    SELECT
        fpp.subject_id,
        fpp.hadm_id,
        fpp.admittime,
        fpp.dischtime,
        fpp.hospital_expire_flag,
        le.charttime,
        le.itemid,
        le.valuenum,
        le.flag
    FROM
        FemalePEPatients fpp
    INNER JOIN
        `physionet-data.mimiciv_3_1_hosp.labevents` le
        ON fpp.subject_id = le.subject_id AND fpp.hadm_id = le.hadm_id
    WHERE
        le.charttime BETWEEN fpp.admittime AND DATETIME_ADD(fpp.admittime, INTERVAL 72 HOUR)
        AND le.valuenum IS NOT NULL -- Only consider labs with numeric values for instability
),
-- CTE 3: Calculate lab instability score and LOS for each admission
AdmissionLabScores AS (
    SELECT
        hadm_id,
        subject_id,
        admittime,
        dischtime,
        hospital_expire_flag,
        COUNT(charttime) AS total_labs_72hr,
        COUNTIF(flag = 'abnormal') AS abnormal_labs_72hr,
        -- Lab instability score: proportion of abnormal labs within 72 hours
        SAFE_DIVIDE(COUNTIF(flag = 'abnormal'), COUNT(charttime)) AS lab_instability_score,
        DATETIME_DIFF(dischtime, admittime, HOUR) / 24.0 AS los_days
    FROM
        LabsForCohort
    GROUP BY
        hadm_id, subject_id, admittime, dischtime, hospital_expire_flag
    HAVING
        COUNT(charttime) > 0 -- Ensure there's at least one lab to calculate a score
),
-- CTE 4: Represents the overall cohort for metrics and percentile calculation
OverallCohortMetrics AS (
    SELECT
        hadm_id,
        subject_id,
        hospital_expire_flag,
        los_days,
        total_labs_72hr,
        abnormal_labs_72hr,
        lab_instability_score
    FROM
        AdmissionLabScores
),
-- CTE 5: Calculate the 75th percentile of the lab instability score
PercentileThreshold AS (
    SELECT
        PERCENTILE_CONT(lab_instability_score, 0.75) AS p75_instability_score -- Corrected PERCENTILE_CONT usage
    FROM
        OverallCohortMetrics
),
-- CTE 6: Identify patients whose lab instability score is at or above the 75th percentile
HighInstabilityCohortMetrics AS (
    SELECT
        ocm.hadm_id,
        ocm.subject_id,
        ocm.hospital_expire_flag,
        ocm.los_days,
        ocm.total_labs_72hr,
        ocm.abnormal_labs_72hr,
        ocm.lab_instability_score
    FROM
        OverallCohortMetrics ocm
    CROSS JOIN
        PercentileThreshold pt
    WHERE
        ocm.lab_instability_score >= pt.p75_instability_score
)
-- Final SELECT statement to present the results
SELECT
    'Female inpatients aged 53-63 with PE and lab instability score >= 75th percentile' AS cohort_description,
    pt.p75_instability_score AS percentile_75_instability_threshold,
    COUNT(DISTINCT hicm.hadm_id) AS num_admissions_above_threshold,
    -- Mortality for patients above threshold
    SAFE_DIVIDE(COUNTIF(hicm.hospital_expire_flag = 1), COUNT(DISTINCT hicm.hadm_id)) * 100 AS mortality_percent_above_threshold, -- Simplified COUNTIF
    -- Mean LOS for patients above threshold
    AVG(hicm.los_days) AS mean_los_days_above_threshold,
    -- Critical-lab rates for patients above threshold (percentage of all 72hr labs flagged abnormal)
    SAFE_DIVIDE(SUM(CAST(hicm.abnormal_labs_72hr AS BIGNUMERIC)), SUM(CAST(hicm.total_labs_72hr AS BIGNUMERIC))) * 100 AS critical_lab_rate_above_threshold_percent,
    -- Critical-lab rates for overall cohort (percentage of all 72hr labs flagged abnormal)
    (SELECT SAFE_DIVIDE(SUM(CAST(ocm.abnormal_labs_72hr AS BIGNUMERIC)), SUM(CAST(ocm.total_labs_72hr AS BIGNUMERIC))) * 100 FROM OverallCohortMetrics ocm) AS critical_lab_rate_overall_cohort_percent
FROM
    HighInstabilityCohortMetrics hicm
CROSS JOIN
    PercentileThreshold pt
GROUP BY
    pt.p75_instability_score;