WITH PatientsWithAsthma AS (
    -- Identify unique admissions for female patients aged 88-98 with an asthma diagnosis
    SELECT DISTINCT
        adm.subject_id,
        adm.hadm_id,
        adm.admittime,
        adm.dischtime,
        DATE_DIFF(adm.dischtime, adm.admittime, DAY) AS los_days
    FROM
        `physionet-data.mimiciv_3_1_hosp`.admissions AS adm
    INNER JOIN
        `physionet-data.mimiciv_3_1_hosp`.patients AS p
        ON adm.subject_id = p.subject_id
    INNER JOIN
        `physionet-data.mimiciv_3_1_hosp`.diagnoses_icd AS di
        ON adm.hadm_id = di.hadm_id
    WHERE
        p.gender = 'F'
        AND p.anchor_age BETWEEN 88 AND 98
        -- ICD-9 codes for asthma start with 493, ICD-10 codes start with J45
        AND (
            (di.icd_version = 9 AND di.icd_code LIKE '493%') OR
            (di.icd_version = 10 AND di.icd_code LIKE 'J45%')
        )
),
AdmissionsLOSCategory AS (
    -- Categorize admissions by length of stay (LOS)
    SELECT
        hadm_id,
        los_days,
        CASE
            WHEN los_days >= 1 AND los_days <= 3 THEN '1-3 days'
            WHEN los_days >= 4 AND los_days <= 7 THEN '4-7 days'
            ELSE 'Other' -- Temporarily categorize others to be filtered later
        END AS los_group
    FROM
        PatientsWithAsthma
    WHERE
        los_days >= 1 AND los_days <= 7 -- Only interested in 1 to 7 day stays
),
ProceduresPerAdmission AS (
    -- Count diagnostic procedures for each qualifying admission, including those with zero procedures
    SELECT
        alc.hadm_id,
        alc.los_group,
        COUNT(proc.icd_code) AS num_diagnostic_procedures -- COUNT(icd_code) will be 0 if no procedures match due to LEFT JOIN
    FROM
        AdmissionsLOSCategory AS alc
    LEFT JOIN
        `physionet-data.mimiciv_3_1_hosp`.procedures_icd AS proc
        ON alc.hadm_id = proc.hadm_id
    GROUP BY
        alc.hadm_id,
        alc.los_group
)
-- Calculate the 25th, 50th (median), and 75th percentiles of diagnostic procedures
-- per admission, partitioned by LOS group.
SELECT DISTINCT
    los_group,
    PERCENTILE_CONT(num_diagnostic_procedures, 0.25) OVER (PARTITION BY los_group) AS percentile_25,
    PERCENTILE_CONT(num_diagnostic_procedures, 0.50) OVER (PARTITION BY los_group) AS percentile_50,
    PERCENTILE_CONT(num_diagnostic_procedures, 0.75) OVER (PARTITION BY los_group) AS percentile_75
FROM
    ProceduresPerAdmission
WHERE
    los_group IN ('1-3 days', '4-7 days') -- Ensure only relevant LOS categories are included
ORDER BY
    los_group;