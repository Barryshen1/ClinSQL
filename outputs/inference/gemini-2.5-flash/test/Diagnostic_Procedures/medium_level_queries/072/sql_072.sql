WITH patient_admissions AS (
    SELECT
        p.subject_id,
        p.gender,
        p.anchor_age,
        adm.hadm_id,
        adm.admittime,
        adm.dischtime
    FROM
        `physionet-data.mimiciv_3_1_hosp.patients` p
    INNER JOIN
        `physionet-data.mimiciv_3_1_hosp.admissions` adm
        ON p.subject_id = adm.subject_id
    WHERE
        p.gender = 'F'
        AND p.anchor_age BETWEEN 52 AND 62
),
-- CTE 2: Identify for each admission whether acute pancreatitis diagnosis is primary or secondary
pancreatitis_flags_per_admission AS (
    SELECT
        pa.hadm_id,
        -- Flag if acute pancreatitis is the primary diagnosis (seq_num = 1)
        MAX(CASE
                WHEN diag.seq_num = 1
                AND (
                    (diag.icd_version = 9 AND diag.icd_code = '5770') -- ICD-9 for Acute pancreatitis
                    OR (diag.icd_version = 10 AND STARTS_WITH(diag.icd_code, 'K85')) -- ICD-10 for Acute pancreatitis (K85.x)
                )
                THEN 1
                ELSE 0
            END) AS has_primary_pancreatitis_diag,
        -- Flag if acute pancreatitis is a secondary diagnosis (seq_num > 1)
        MAX(CASE
                WHEN diag.seq_num > 1
                AND (
                    (diag.icd_version = 9 AND diag.icd_code = '5770')
                    OR (diag.icd_version = 10 AND STARTS_WITH(diag.icd_code, 'K85'))
                )
                THEN 1
                ELSE 0
            END) AS has_secondary_pancreatitis_diag
    FROM
        patient_admissions pa
    INNER JOIN
        `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` diag
        ON pa.subject_id = diag.subject_id AND pa.hadm_id = diag.hadm_id
    GROUP BY
        pa.hadm_id
    HAVING
        -- Ensure that there is at least one acute pancreatitis diagnosis for the admission
        MAX(CASE
                WHEN (diag.icd_version = 9 AND diag.icd_code = '5770')
                OR (diag.icd_version = 10 AND STARTS_WITH(diag.icd_code, 'K85'))
                THEN 1
                ELSE 0
            END) = 1
),
-- CTE 3: Filter the cohort based on pancreatitis diagnosis status, calculate LOS, and assign duration groups
filtered_pancreatitis_cohort AS (
    SELECT
        pa.subject_id,
        pa.hadm_id,
        pa.admittime,
        pa.dischtime,
        DATE_DIFF(pa.dischtime, pa.admittime, DAY) AS los_days,
        -- Assign diagnosis type group (Primary vs Secondary) based on flags from CTE 2
        CASE
            WHEN pfa.has_primary_pancreatitis_diag = 1 THEN 'Primary Pancreatitis'
            WHEN pfa.has_primary_pancreatitis_diag = 0 AND pfa.has_secondary_pancreatitis_diag = 1 THEN 'Secondary Pancreatitis'
            ELSE NULL -- This case should ideally not be reached due to HAVING clause in CTE 2
        END AS diagnosis_type_group,
        -- Assign duration group based on calculated LOS
        CASE
            WHEN DATE_DIFF(pa.dischtime, pa.admittime, DAY) BETWEEN 1 AND 4 THEN '1-4 days'
            WHEN DATE_DIFF(pa.dischtime, pa.admittime, DAY) BETWEEN 5 AND 8 THEN '5-8 days'
            ELSE NULL
        END AS duration_group
    FROM
        patient_admissions pa
    INNER JOIN
        pancreatitis_flags_per_admission pfa
        ON pa.hadm_id = pfa.hadm_id
    WHERE
        DATE_DIFF(pa.dischtime, pa.admittime, DAY) IS NOT NULL
        AND DATE_DIFF(pa.dischtime, pa.admittime, DAY) BETWEEN 1 AND 8 -- Filter for desired LOS range
        AND (
            (pfa.has_primary_pancreatitis_diag = 1) OR
            (pfa.has_primary_pancreatitis_diag = 0 AND pfa.has_secondary_pancreatitis_diag = 1)
        ) -- Ensure only relevant diagnosis type groups are included
),
-- CTE 4: Count distinct diagnostic procedures for each HADM_ID in the filtered cohort
admission_procedure_counts AS (
    SELECT
        fpc.hadm_id,
        COUNT(DISTINCT proc.icd_code) AS procedure_count
    FROM
        filtered_pancreatitis_cohort fpc
    LEFT JOIN
        `physionet-data.mimiciv_3_1_hosp.procedures_icd` proc
        ON fpc.subject_id = proc.subject_id AND fpc.hadm_id = proc.hadm_id
    GROUP BY
        fpc.hadm_id
)
-- Final SELECT: Aggregate the results by duration group and diagnosis type group
SELECT
    fpc.duration_group,
    fpc.diagnosis_type_group,
    COUNT(DISTINCT fpc.hadm_id) AS num_admissions,
    AVG(apc.procedure_count) AS mean_procedures_per_admission,
    MIN(apc.procedure_count) AS min_procedures_per_admission,
    MAX(apc.procedure_count) AS max_procedures_per_admission
FROM
    filtered_pancreatitis_cohort fpc
INNER JOIN
    admission_procedure_counts apc
    ON fpc.hadm_id = apc.hadm_id
WHERE
    fpc.duration_group IS NOT NULL -- Exclude admissions outside the 1-8 day LOS category
    AND fpc.diagnosis_type_group IS NOT NULL -- Exclude any unclassified diagnosis groups
GROUP BY
    fpc.duration_group,
    fpc.diagnosis_type_group
ORDER BY
    fpc.duration_group,
    fpc.diagnosis_type_group;