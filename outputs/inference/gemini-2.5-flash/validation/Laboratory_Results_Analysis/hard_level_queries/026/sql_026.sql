WITH base_admissions AS (
    SELECT
        p.subject_id,
        ad.hadm_id,
        ad.admittime,
        ad.dischtime,
        ad.hospital_expire_flag
    FROM
        `physionet-data.mimiciv_3_1_hosp`.patients p
    INNER JOIN
        `physionet-data.mimiciv_3_1_hosp`.admissions ad
        ON p.subject_id = ad.subject_id
    WHERE
        p.gender = 'M'
        AND p.anchor_age BETWEEN 75 AND 85
),
-- Step 2: Identify admissions from the base_admissions group that have a Hepatic Failure diagnosis
hepatic_failure_hadms AS (
    SELECT DISTINCT
        ba.hadm_id
    FROM
        base_admissions ba
    INNER JOIN
        `physionet-data.mimiciv_3_1_hosp`.diagnoses_icd di
        ON ba.hadm_id = di.hadm_id
    WHERE
        (di.icd_version = 9 AND di.icd_code IN ('570', '5722', '5733')) -- ICD-9 codes for hepatic failure: Acute and subacute hepatic necrosis, Hepatic failure unspecified, Toxic liver disease with hepatic failure
        OR (di.icd_version = 10 AND di.icd_code IN ('K704', 'K720', 'K721', 'K729')) -- ICD-10 codes for hepatic failure: Alcoholic hepatic failure, Acute and subacute hepatic failure, Chronic hepatic failure, Hepatic failure unspecified
),
-- Step 3: Classify each base admission as "Hepatic Failure Cohort" or "General Inpatients Cohort"
-- The "General Inpatients Cohort" consists of male inpatients aged 75-85 WITHOUT a hepatic failure diagnosis.
classified_admissions AS (
    SELECT
        ba.subject_id,
        ba.hadm_id,
        ba.admittime,
        ba.dischtime,
        ba.hospital_expire_flag,
        CASE
            WHEN hf.hadm_id IS NOT NULL THEN 'Hepatic Failure Cohort'
            ELSE 'General Inpatients Cohort'
        END AS cohort_group
    FROM
        base_admissions ba
    LEFT JOIN
        hepatic_failure_hadms hf
        ON ba.hadm_id = hf.hadm_id
),
-- Step 4: Retrieve DRG severity for each classified admission. MAX is used if multiple DRG codes exist.
admissions_with_drg AS (
    SELECT
        ca.subject_id,
        ca.hadm_id,
        ca.admittime,
        ca.dischtime,
        ca.hospital_expire_flag,
        ca.cohort_group,
        MAX(drg.drg_severity) AS drg_severity_per_admission -- Proxy for instability score, taking the highest severity if multiple DRGs
    FROM
        classified_admissions ca
    LEFT JOIN
        `physionet-data.mimiciv_3_1_hosp`.drgcodes drg
        ON ca.hadm_id = drg.hadm_id
    GROUP BY
        ca.subject_id, ca.hadm_id, ca.admittime, ca.dischtime, ca.hospital_expire_flag, ca.cohort_group
),
-- Step 5: Count critical lab events for each admission within the first 48 hours
critical_lab_counts AS (
    SELECT
        awd.hadm_id,
        COUNT(le.labevent_id) AS critical_lab_events_48hr
    FROM
        admissions_with_drg awd
    INNER JOIN
        `physionet-data.mimiciv_3_1_hosp`.labevents le
        ON awd.hadm_id = le.hadm_id
    WHERE
        le.charttime BETWEEN awd.admittime AND DATETIME_ADD(awd.admittime, INTERVAL 48 HOUR)
        AND le.flag IN ('L', 'H') -- Filter for critical (low/high) labs
    GROUP BY
        awd.hadm_id
)
-- Final aggregation to calculate requested metrics for both cohorts
SELECT
    awd.cohort_group,
    COUNT(DISTINCT awd.hadm_id) AS num_admissions,
    MAX(awd.drg_severity_per_admission) AS cohort_maximum_instability_score, -- Max DRG severity observed in any admission within the cohort
    SAFE_DIVIDE(SUM(awd.hospital_expire_flag), COUNT(awd.hadm_id)) AS hospital_mortality_rate,
    AVG(DATETIME_DIFF(awd.dischtime, awd.admittime, HOUR) / 24.0) AS average_hospital_los_days,
    AVG(COALESCE(clc.critical_lab_events_48hr, 0)) AS avg_critical_lab_events_per_admission_48hr
FROM
    admissions_with_drg awd
LEFT JOIN
    critical_lab_counts clc
    ON awd.hadm_id = clc.hadm_id
GROUP BY
    awd.cohort_group
ORDER BY
    awd.cohort_group;