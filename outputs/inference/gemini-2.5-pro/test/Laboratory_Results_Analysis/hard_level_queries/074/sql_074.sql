WITH
-- Step 1: Identify all male hospital admissions within the specified age range
male_patients_in_age_range AS (
    SELECT
        a.subject_id,
        a.hadm_id,
        a.admittime,
        a.dischtime,
        a.hospital_expire_flag
    FROM
        `physionet-data.mimiciv_3_1_hosp.patients` AS p
    INNER JOIN
        `physionet-data.mimiciv_3_1_hosp.admissions` AS a
        ON p.subject_id = a.subject_id
    WHERE
        p.gender = 'M'
        -- Calculate age at admission and filter for the 37-47 age group
        AND (p.anchor_age + EXTRACT(YEAR FROM a.admittime) - p.anchor_year) BETWEEN 37 AND 47
),

-- Step 2: Identify admissions with a diagnosis of heart failure
hf_admissions AS (
    SELECT DISTINCT
        diag.hadm_id
    FROM
        `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` AS diag
    INNER JOIN
        `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` AS d
        ON diag.icd_code = d.icd_code AND diag.icd_version = d.icd_version
    WHERE
        -- Use LOWER for case-insensitive matching of 'heart failure'
        LOWER(d.long_title) LIKE '%heart failure%'
),

-- Step 3: Combine the base cohort with the heart failure diagnosis flag
cohort_base AS (
    SELECT
        mp.subject_id,
        mp.hadm_id,
        mp.admittime,
        mp.dischtime,
        mp.hospital_expire_flag,
        CASE
            WHEN hf.hadm_id IS NOT NULL THEN 1
            ELSE 0
        END AS is_hf_patient
    FROM
        male_patients_in_age_range AS mp
    LEFT JOIN
        hf_admissions AS hf
        ON mp.hadm_id = hf.hadm_id
),

-- Step 4: Calculate the "laboratory instability score" for each patient
-- This is the count of unique critically abnormal labs in the first 72 hours
lab_scores AS (
    SELECT
        le.hadm_id,
        COUNT(DISTINCT le.itemid) AS instability_score
    FROM
        `physionet-data.mimiciv_3_1_hosp.labevents` AS le
    INNER JOIN
        cohort_base AS cb -- Only calculate scores for patients in our base cohort
        ON le.hadm_id = cb.hadm_id
    WHERE
        -- Lab result is flagged as abnormal
        le.flag = 'abnormal'
        -- Lab was charted within the first 72 hours of admission
        AND le.charttime BETWEEN cb.admittime AND DATETIME_ADD(cb.admittime, INTERVAL 72 HOUR)
    GROUP BY
        le.hadm_id
),

-- Step 5: Prepare data for final aggregation by creating two labeled sets
-- One for the 'Heart Failure' group and one for the 'General Inpatients' group
labeled_cohorts AS (
    -- The full cohort of "General Inpatients"
    SELECT
        'General Inpatients' AS cohort_name,
        cb.hadm_id,
        DATETIME_DIFF(cb.dischtime, cb.admittime, HOUR) / 24.0 AS los_days,
        cb.hospital_expire_flag,
        COALESCE(ls.instability_score, 0) AS instability_score
    FROM
        cohort_base AS cb
    LEFT JOIN
        lab_scores AS ls
        ON cb.hadm_id = ls.hadm_id

    UNION ALL

    -- The subset of patients with Heart Failure
    SELECT
        'Heart Failure' AS cohort_name,
        cb.hadm_id,
        DATETIME_DIFF(cb.dischtime, cb.admittime, HOUR) / 24.0 AS los_days,
        cb.hospital_expire_flag,
        COALESCE(ls.instability_score, 0) AS instability_score
    FROM
        cohort_base AS cb
    LEFT JOIN
        lab_scores AS ls
        ON cb.hadm_id = ls.hadm_id
    WHERE
        cb.is_hf_patient = 1
)

-- Final Step: Aggregate the metrics for each cohort
SELECT
    cohort_name,
    MAX(instability_score) AS max_instability_score,
    -- "Critical-event rate" is interpreted as the average instability score
    AVG(instability_score) AS avg_instability_score_aka_critical_event_rate,
    -- Average Length of Stay in days
    AVG(los_days) AS avg_los_days,
    -- Hospital mortality rate
    AVG(CAST(hospital_expire_flag AS FLOAT64)) AS mortality_rate
FROM
    labeled_cohorts
GROUP BY
    cohort_name
ORDER BY
    -- Show 'Heart Failure' first for easier comparison
    cohort_name DESC;