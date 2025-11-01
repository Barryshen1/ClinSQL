SELECT
    CASE
        WHEN apa.los_days >= 1 AND apa.los_days <= 4 THEN 'LOS 1-4 days'
        WHEN apa.los_days >= 5 AND apa.los_days <= 8 THEN 'LOS 5-8 days'
        ELSE 'Other LOS' -- This category will be excluded by the final WHERE clause, but included for logical completeness.
    END AS los_group,
    COUNT(DISTINCT apa.subject_id) AS distinct_patient_count,
    COUNT(apa.hadm_id) AS admission_count,
    ROUND(AVG(COALESCE(awc.num_ct_mri_procedures, 0)), 2) AS mean_ct_mri_procedures_per_admission
FROM
    -- Step 1: Filter patients by demographics
    (
        SELECT
            p.subject_id,
            a.hadm_id,
            a.admittime,
            a.dischtime,
            p.anchor_age + (EXTRACT(YEAR FROM a.admittime) - p.anchor_year) AS admission_age
        FROM
            `physionet-data.mimiciv_3_1_hosp.patients` p
        INNER JOIN
            `physionet-data.mimiciv_3_1_hosp.admissions` a
            ON p.subject_id = a.subject_id
        WHERE
            p.gender = 'F'
            AND (p.anchor_age + (EXTRACT(YEAR FROM a.admittime) - p.anchor_year)) BETWEEN 47 AND 57
            AND a.dischtime IS NOT NULL -- Ensure admission is complete to calculate LOS
    ) AS patients_initial_filter
INNER JOIN
    -- Step 2: Identify acute pancreatitis admissions
    (
        SELECT
            pif.subject_id,
            pif.hadm_id,
            pif.admittime,
            pif.dischtime,
            DATETIME_DIFF(pif.dischtime, pif.admittime, DAY) AS los_days
        FROM
            (
                SELECT
                    p.subject_id,
                    a.hadm_id,
                    a.admittime,
                    a.dischtime,
                    p.anchor_age + (EXTRACT(YEAR FROM a.admittime) - p.anchor_year) AS admission_age
                FROM
                    `physionet-data.mimiciv_3_1_hosp.patients` p
                INNER JOIN
                    `physionet-data.mimiciv_3_1_hosp.admissions` a
                    ON p.subject_id = a.subject_id
                WHERE
                    p.gender = 'F'
                    AND (p.anchor_age + (EXTRACT(YEAR FROM a.admittime) - p.anchor_year)) BETWEEN 47 AND 57
                    AND a.dischtime IS NOT NULL
            ) AS pif
        INNER JOIN
            `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` di
            ON pif.subject_id = di.subject_id AND pif.hadm_id = di.hadm_id
        WHERE
            -- ICD-10 codes for Acute Pancreatitis (K85.x)
            di.icd_version = 10 AND di.icd_code LIKE 'K85%'
        GROUP BY
            pif.subject_id, pif.hadm_id, pif.admittime, pif.dischtime
    ) AS apa
    ON patients_initial_filter.hadm_id = apa.hadm_id
LEFT JOIN
    -- Step 3 & 4: Count CT/MRI procedures per admission
    (
        SELECT
            proc.hadm_id,
            COUNT(proc.icd_code) AS num_ct_mri_procedures
        FROM
            `physionet-data.mimiciv_3_1_hosp.procedures_icd` proc
        INNER JOIN
            -- Identify all ICD procedure codes related to CT/MRI
            (
                SELECT DISTINCT
                    dicd.icd_code,
                    dicd.icd_version
                FROM
                    `physionet-data.mimiciv_3_1_hosp.d_icd_procedures` dicd
                WHERE
                    (lower(dicd.long_title) LIKE '%computed tomography%' OR lower(dicd.long_title) LIKE '%ct scan%')
                    OR (lower(dicd.long_title) LIKE '%magnetic resonance imaging%' OR lower(dicd.long_title) LIKE '%mri%')
            ) AS cmc
            ON proc.icd_code = cmc.icd_code AND proc.icd_version = cmc.icd_version
        GROUP BY
            proc.hadm_id
    ) AS awc
    ON apa.hadm_id = awc.hadm_id
WHERE
    apa.los_days >= 1 AND apa.los_days <= 8 -- Filter for the specified LOS ranges
GROUP BY
    los_group
ORDER BY
    los_group;