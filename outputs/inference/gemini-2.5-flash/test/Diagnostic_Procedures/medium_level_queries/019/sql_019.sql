WITH AdmissionsFiltered AS (
    -- Step 1: Identify eligible admissions based on gender, age, and acute pancreatitis diagnosis
    SELECT DISTINCT
        adm.subject_id,
        adm.hadm_id,
        adm.admittime,
        adm.dischtime
    FROM
        `physionet-data.mimiciv_3_1_hosp.admissions` AS adm
    JOIN
        `physionet-data.mimiciv_3_1_hosp.patients` AS pat
        ON adm.subject_id = pat.subject_id
    WHERE
        pat.gender = 'M'
        AND pat.anchor_age BETWEEN 42 AND 52
        -- Filter for admissions with an acute pancreatitis diagnosis
        AND EXISTS (
            SELECT 1
            FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` AS di
            WHERE
                di.hadm_id = adm.hadm_id
                AND (
                    (di.icd_version = 10 AND di.icd_code LIKE 'K85%') -- ICD-10 codes for Acute Pancreatitis
                    OR (di.icd_version = 9 AND di.icd_code = '5770') -- ICD-9 code for Acute Pancreatitis
                )
        )
),
AdmissionsWithLOS AS (
    -- Step 2: Calculate Length of Stay (LOS) and assign to specified groups
    SELECT
        af.subject_id,
        af.hadm_id,
        DATE_DIFF(af.dischtime, af.admittime, DAY) AS los_days,
        CASE
            WHEN DATE_DIFF(af.dischtime, af.admittime, DAY) BETWEEN 1 AND 4 THEN '1-4 days'
            WHEN DATE_DIFF(af.dischtime, af.admittime, DAY) BETWEEN 5 AND 7 THEN '5-7 days'
            ELSE NULL -- Filter out admissions not in the target LOS ranges
        END AS los_group
    FROM
        AdmissionsFiltered AS af
    WHERE
        -- Ensure LOS is positive and falls within the range relevant for grouping
        DATE_DIFF(af.dischtime, af.admittime, DAY) BETWEEN 1 AND 7
),
ProceduresPerAdmission AS (
    -- Step 3: Count diagnostic procedures for each eligible admission
    SELECT
        awl.hadm_id,
        awl.subject_id,
        awl.los_group,
        COUNT(proc.icd_code) AS procedure_count -- Count of procedure records for each admission
    FROM
        AdmissionsWithLOS AS awl
    LEFT JOIN
        `physionet-data.mimiciv_3_1_hosp.procedures_icd` AS proc
        ON awl.hadm_id = proc.hadm_id
    WHERE
        awl.los_group IS NOT NULL -- Ensures only admissions in valid LOS groups are considered
    GROUP BY
        awl.hadm_id, awl.subject_id, awl.los_group
)
-- Step 4: Aggregate results by LOS group
SELECT
    ppa.los_group,
    COUNT(DISTINCT ppa.subject_id) AS patient_count,
    ROUND(AVG(ppa.procedure_count), 2) AS mean_diagnostic_procedures_per_admission,
    MIN(ppa.procedure_count) AS min_diagnostic_procedures_per_admission,
    MAX(ppa.procedure_count) AS max_diagnostic_procedures_per_admission
FROM
    ProceduresPerAdmission AS ppa
GROUP BY
    ppa.los_group
ORDER BY
    ppa.los_group;