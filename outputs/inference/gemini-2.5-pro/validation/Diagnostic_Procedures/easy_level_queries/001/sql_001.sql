WITH patient_cohort AS (
    SELECT
        p.subject_id
    FROM
        `physionet-data.mimiciv_3_1_hosp.patients` AS p
    WHERE
        p.gender = 'M'
        AND p.anchor_age BETWEEN 63 AND 73
),

-- Step 2: Get all hospital admissions for this patient cohort.
-- This defines our base population for the analysis.
cohort_admissions AS (
    SELECT
        a.hadm_id
    FROM
        `physionet-data.mimiciv_3_1_hosp.admissions` AS a
    INNER JOIN
        patient_cohort AS pc
        ON a.subject_id = pc.subject_id
),

-- Step 3: Identify all ICD codes that correspond to a cardiac procedure
-- based on keywords in their description.
cardiac_icd_codes AS (
    SELECT
        d.icd_code,
        d.icd_version
    FROM
        `physionet-data.mimiciv_3_1_hosp.d_icd_procedures` AS d
    WHERE
        -- Use REGEXP_CONTAINS for a broad but relevant search of cardiac-related terms.
        REGEXP_CONTAINS(LOWER(d.long_title), 'cardiac|heart|coronary|atrial|atrium|ventricular|valve|pericardial|aortic|aorta')
),

-- Step 4: Link the identified cardiac procedures to the hospitalizations where they were performed.
cardiac_procedures_performed AS (
    SELECT
        p.hadm_id,
        p.icd_code
    FROM
        `physionet-data.mimiciv_3_1_hosp.procedures_icd` AS p
    INNER JOIN
        cardiac_icd_codes AS cic
        ON p.icd_code = cic.icd_code AND p.icd_version = cic.icd_version
),

-- Step 5: Count the number of distinct cardiac procedures for each hospitalization in the cohort.
-- A LEFT JOIN ensures we include hospitalizations with zero cardiac procedures.
counts_per_admission AS (
    SELECT
        ca.hadm_id,
        COUNT(DISTINCT cpp.icd_code) AS num_distinct_cardiac_procedures
    FROM
        cohort_admissions AS ca
    LEFT JOIN
        cardiac_procedures_performed AS cpp
        ON ca.hadm_id = cpp.hadm_id
    GROUP BY
        ca.hadm_id
)

-- Final Step: Calculate the 75th percentile of the counts.
SELECT
    APPROX_QUANTILES(num_distinct_cardiac_procedures, 100)[OFFSET(75)] AS p75_distinct_cardiac_procedures
FROM
    counts_per_admission;