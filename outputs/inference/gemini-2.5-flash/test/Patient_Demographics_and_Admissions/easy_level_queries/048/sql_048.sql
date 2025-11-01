WITH Patient_Cohort AS (
    -- Step 1: Identify all unique patients conforming to the demographic and diagnosis criteria.
    -- These are female patients, aged 79-89, who have had at least one heart failure diagnosis across any of their admissions.
    SELECT DISTINCT
        p.subject_id
    FROM
        `physionet-data.mimiciv_3_1_hosp.patients` p
    JOIN
        `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` di
        ON p.subject_id = di.subject_id
    WHERE
        p.gender = 'F'
        AND p.anchor_age BETWEEN 79 AND 89
        AND (
            (di.icd_version = 10 AND di.icd_code LIKE 'I50%') -- ICD-10 codes for Heart Failure
            OR (di.icd_version = 9 AND di.icd_code LIKE '428%') -- ICD-9 codes for Heart Failure
        )
),
First_Admission_LOS AS (
    -- Step 2: For each patient in the cohort, find their very first hospital admission and calculate its Length of Stay (LOS).
    SELECT
        a.subject_id,
        a.hadm_id,
        TIMESTAMP_DIFF(a.dischtime, a.admittime, DAY) AS los_days,
        ROW_NUMBER() OVER (PARTITION BY a.subject_id ORDER BY a.admittime) AS rn
    FROM
        `physionet-data.mimiciv_3_1_hosp.admissions` a
    JOIN
        Patient_Cohort pc
        ON a.subject_id = pc.subject_id
    WHERE
        a.dischtime IS NOT NULL AND a.admittime IS NOT NULL -- Exclude records with missing admission/discharge times
        AND TIMESTAMP_DIFF(a.dischtime, a.admittime, DAY) >= 0 -- Ensure positive LOS (dischtime > admittime)
)
-- Step 3: Calculate the Interquartile Range (IQR) of the first admission LOS for the selected patient cohort.
SELECT
    PERCENTILE_CONT(los_days, 0.75) OVER() - PERCENTILE_CONT(los_days, 0.25) OVER() AS iqr_first_admission_los_days
FROM
    First_Admission_LOS
WHERE
    rn = 1 -- Select only the first admission for each patient in the cohort
LIMIT 1; -- We only need one row as the IQR is a single value over the entire set;