WITH patient_cohort AS (
    -- 1. Identify the patient cohort: female, 71-81 years old, with valid LOS
    SELECT
        p.subject_id,
        adm.hadm_id,
        adm.admittime,
        adm.dischtime,
        DATETIME_DIFF(adm.dischtime, adm.admittime, DAY) AS los_days,
        CASE
            WHEN DATETIME_DIFF(adm.dischtime, adm.admittime, DAY) BETWEEN 1 AND 3 THEN '1-3 days'
            WHEN DATETIME_DIFF(adm.dischtime, adm.admittime, DAY) BETWEEN 4 AND 7 THEN '4-7 days'
            ELSE NULL -- Exclude admissions outside 1-7 days LOS
        END AS los_group
    FROM
        `physionet-data.mimiciv_3_1_hosp.patients` AS p
    INNER JOIN
        `physionet-data.mimiciv_3_1_hosp.admissions` AS adm
        ON p.subject_id = adm.subject_id
    WHERE
        p.gender = 'F'
        AND p.anchor_age BETWEEN 71 AND 81
        AND adm.admittime IS NOT NULL
        AND adm.dischtime IS NOT NULL
),
lgib_admissions_raw AS (
    -- 2. Filter for potential Lower GI Bleed (LGIB) diagnoses within the cohort
    SELECT
        pc.hadm_id,
        pc.los_group,
        diag.seq_num,
        diag.icd_version,
        diag.icd_code
    FROM
        patient_cohort AS pc
    INNER JOIN
        `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` AS diag
        ON pc.subject_id = diag.subject_id AND pc.hadm_id = diag.hadm_id
    WHERE
        pc.los_group IS NOT NULL -- Only process admissions within the target LOS range
        AND (
            -- ICD-10 codes for LGIB (MIMIC-IV stores without periods)
            (diag.icd_version = 10 AND (
                diag.icd_code IN ('K921', 'K922', 'K625', 'K5521')
                OR (SUBSTR(diag.icd_code, 1, 3) = 'K57' AND SUBSTR(diag.icd_code, 5, 1) IN ('2', '4')) -- K57.XX2/K57.XX4
            ))
            OR
            -- ICD-9 codes for LGIB (MIMIC-IV stores without periods)
            (diag.icd_version = 9 AND (
                diag.icd_code IN ('5781', '5789', '5693', '56211', '56213', '53783') -- 53783 for angiodysplasia
            ))
        )
),
lgib_admissions_with_priority_flags AS (
    -- Determine LGIB priority for each admission
    SELECT
        hadm_id,
        los_group,
        MAX(CASE WHEN seq_num = 1 THEN 1 ELSE 0 END) AS has_primary_lgib,
        MAX(CASE WHEN seq_num > 1 THEN 1 ELSE 0 END) AS has_secondary_lgib
    FROM
        lgib_admissions_raw
    GROUP BY
        hadm_id, los_group
),
final_lgib_cohort AS (
    -- Assign the final LGIB diagnosis priority group
    SELECT
        hadm_id,
        los_group,
        CASE
            WHEN has_primary_lgib = 1 THEN 'Primary LGIB'
            WHEN has_secondary_lgib = 1 THEN 'Secondary LGIB'
            ELSE 'Unknown LGIB Priority' -- Should not be reached if filtered correctly above
        END AS diagnosis_priority_group
    FROM
        lgib_admissions_with_priority_flags
    WHERE
        has_primary_lgib = 1 OR has_secondary_lgib = 1 -- Ensure truly a classified LGIB admission
),
radiology_counts AS (
    -- 3. Count radiography/CT scans per admission for the LGIB cohort
    SELECT
        flc.hadm_id,
        -- Count each procedure record / instance that matches radiology criteria
        COUNT(proc.icd_code) AS radiology_count
    FROM
        final_lgib_cohort AS flc
    INNER JOIN
        `physionet-data.mimiciv_3_1_hosp.procedures_icd` AS proc
        ON flc.hadm_id = proc.hadm_id
    INNER JOIN
        `physionet-data.mimiciv_3_1_hosp.d_icd_procedures` AS dicd_proc
        ON proc.icd_code = dicd_proc.icd_code AND proc.icd_version = dicd_proc.icd_version
    WHERE
        LOWER(dicd_proc.long_title) LIKE '%computed tomography%'
        OR LOWER(dicd_proc.long_title) LIKE '%ct scan%'
        OR LOWER(dicd_proc.long_title) LIKE '%radiograph%'
        OR LOWER(dicd_proc.long_title) LIKE '%x-ray%'
    GROUP BY
        flc.hadm_id
)
-- 4. Aggregate and calculate mean radiography/CT scans
SELECT
    flc.los_group,
    flc.diagnosis_priority_group,
    COUNT(DISTINCT flc.hadm_id) AS number_of_admissions,
    COALESCE(SUM(rc.radiology_count), 0) AS total_radiology_procedures,
    SAFE_DIVIDE(COALESCE(SUM(rc.radiology_count), 0), COUNT(DISTINCT flc.hadm_id)) AS mean_radiology_per_admission
FROM
    final_lgib_cohort AS flc
LEFT JOIN -- Use LEFT JOIN to count admissions with 0 radiology procedures as 0
    radiology_counts AS rc
    ON flc.hadm_id = rc.hadm_id
GROUP BY
    flc.los_group,
    flc.diagnosis_priority_group
ORDER BY
    flc.los_group,
    flc.diagnosis_priority_group;