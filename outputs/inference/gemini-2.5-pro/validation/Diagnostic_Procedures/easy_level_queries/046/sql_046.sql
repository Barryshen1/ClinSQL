WITH patient_cohort_procedures AS (
    -- Step 1 & 2: Select the patient cohort and join with their procedures, filtering for MCS procedures
    SELECT
        p.subject_id,
        proc.icd_code
    FROM
        `physionet-data.mimiciv_3_1_hosp.patients` AS p
    INNER JOIN
        `physionet-data.mimiciv_3_1_hosp.procedures_icd` AS proc
        ON p.subject_id = proc.subject_id
    INNER JOIN
        `physionet-data.mimiciv_3_1_hosp.d_icd_procedures` AS d_proc
        ON proc.icd_code = d_proc.icd_code AND proc.icd_version = d_proc.icd_version
    WHERE
        p.gender = 'M'
        AND p.anchor_age BETWEEN 80 AND 90
        -- Step 3: Define "Mechanical Circulatory Support" using keywords
        AND (
            LOWER(d_proc.long_title) LIKE '%intra-aortic balloon%' OR
            LOWER(d_proc.long_title) LIKE '%extracorporeal membrane oxygenation%' OR
            LOWER(d_proc.long_title) LIKE '%impella%' OR
            LOWER(d_proc.long_title) LIKE '%ventricular assist%' OR
            LOWER(d_proc.long_title) LIKE '%heart assist system%'
        )
),
distinct_counts_per_patient AS (
    -- Step 4: Count the number of distinct MCS procedures for each patient
    SELECT
        subject_id,
        COUNT(DISTINCT icd_code) AS num_distinct_mcs_procedures
    FROM
        patient_cohort_procedures
    GROUP BY
        subject_id
)
-- Step 5: Find the maximum count among all patients in the cohort
SELECT
    MAX(num_distinct_mcs_procedures) AS max_distinct_mcs_procedures
FROM
    distinct_counts_per_patient;