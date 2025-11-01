with Acute Kidney Injury (AKI) and those without.
-- It calculates and compares the mean 72-hour lab instability, critical event frequency, length of stay, and mortality.

WITH
-- Step 1: Create a base population of male patients and calculate their age at admission.
base_population AS (
    SELECT
        p.subject_id,
        adm.hadm_id,
        adm.admittime,
        adm.dischtime,
        adm.hospital_expire_flag,
        -- Calculate age at admission for accuracy
        (EXTRACT(YEAR FROM adm.admittime) - p.anchor_year) + p.anchor_age AS age_at_admission
    FROM
        `physionet-data.mimiciv_3_1_hosp.patients` AS p
    INNER JOIN
        `physionet-data.mimiciv_3_1_hosp.admissions` AS adm
            ON p.subject_id = adm.subject_id
    WHERE
        p.gender = 'M'
),

-- Step 2: Filter the base population to the target age range of 47-57.
age_filtered_population AS (
    SELECT
        subject_id,
        hadm_id,
        admittime,
        dischtime,
        hospital_expire_flag
    FROM
        base_population
    WHERE
        age_at_admission BETWEEN 47 AND 57
),

-- Step 3: Identify all hospital admissions with an AKI diagnosis.
aki_admissions AS (
    SELECT DISTINCT hadm_id
    FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd`
    WHERE
        -- ICD-9 codes for Acute Kidney Failure
        icd_code LIKE '584%'
        -- ICD-10 codes for Acute Kidney Injury
        OR icd_code LIKE 'N17%'
),

-- Step 4: Assign each patient in the age-filtered population to a cohort ('AKI' or 'Control').
cohorts AS (
    SELECT
        pop.subject_id,
        pop.hadm_id,
        pop.admittime,
        pop.dischtime,
        pop.hospital_expire_flag,
        CASE
            WHEN aki.hadm_id IS NOT NULL THEN 'AKI'
            ELSE 'Control'
        END AS cohort_group
    FROM
        age_filtered_population AS pop
    LEFT JOIN
        aki_admissions AS aki
            ON pop.hadm_id = aki.hadm_id
),

-- Step 5: Calculate the 72-hour laboratory instability score for each admission.
-- Definition: Count of distinct lab items flagged as 'abnormal' in the first 72h.
lab_instability AS (
    SELECT
        c.hadm_id,
        COUNT(DISTINCT le.itemid) AS lab_instability_score
    FROM
        cohorts AS c
    INNER JOIN
        `physionet-data.mimiciv_3_1_hosp.labevents` AS le
            ON c.hadm_id = le.hadm_id
    WHERE
        le.charttime BETWEEN c.admittime AND DATETIME_ADD(c.admittime, INTERVAL 72 HOUR)
        AND le.flag = 'abnormal'
    GROUP BY
        c.hadm_id
),

-- Step 6: Calculate the 72-hour critical event frequency for each admission.
-- Definition: Count of chartevents with a 'warning' flag in the first 72h.
critical_events AS (
    SELECT
        c.hadm_id,
        COUNT(ce.itemid) AS critical_event_count
    FROM
        cohorts AS c
    INNER JOIN
        `physionet-data.mimiciv_3_1_icu.chartevents` AS ce
            ON c.hadm_id = ce.hadm_id
    WHERE
        ce.charttime BETWEEN c.admittime AND DATETIME_ADD(c.admittime, INTERVAL 72 HOUR)
        AND ce.warning = 1
    GROUP BY
        c.hadm_id
),

-- Step 7: Combine all metrics for each patient admission.
patient_metrics AS (
    SELECT
        c.hadm_id,
        c.cohort_group,
        c.hospital_expire_flag,
        -- Calculate LOS in days with decimal precision
        DATETIME_DIFF(c.dischtime, c.admittime, HOUR) / 24.0 AS length_of_stay,
        COALESCE(li.lab_instability_score, 0) AS lab_instability_score,
        COALESCE(ce.critical_event_count, 0) AS critical_event_count
    FROM
        cohorts AS c
    LEFT JOIN
        lab_instability AS li
            ON c.hadm_id = li.hadm_id
    LEFT JOIN
        critical_events AS ce
            ON c.hadm_id = ce.hadm_id
)

-- Step 8: Final aggregation to get the summary statistics for each cohort.
SELECT
    cohort_group,
    COUNT(DISTINCT hadm_id) AS number_of_admissions,
    AVG(lab_instability_score) AS mean_72hr_lab_instability_score,
    AVG(critical_event_count) AS mean_72hr_critical_event_frequency,
    AVG(length_of_stay) AS avg_length_of_stay_days,
    AVG(hospital_expire_flag) AS in_hospital_mortality_rate
FROM
    patient_metrics
GROUP BY
    cohort_group
ORDER BY
    cohort_group DESC;