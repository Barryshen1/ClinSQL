WITH
-- 1. Identify hospital admissions for female patients aged 50-60 with a TIA diagnosis.
cohort_admissions AS (
    SELECT DISTINCT
        pat.subject_id,
        adm.hadm_id
    FROM
        `physionet-data.mimiciv_3_1_hosp.patients` AS pat
    INNER JOIN
        `physionet-data.mimiciv_3_1_hosp.admissions` AS adm
        ON pat.subject_id = adm.subject_id
    INNER JOIN
        `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` AS dx
        ON adm.hadm_id = dx.hadm_id
    INNER JOIN
        `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` AS d_dx
        ON dx.icd_code = d_dx.icd_code AND dx.icd_version = d_dx.icd_version
    WHERE
        pat.gender = 'F'
        AND pat.anchor_age BETWEEN 50 AND 60
        AND d_dx.long_title LIKE '%Transient ischemic attack%'
),

-- 2. For the cohort, calculate Length of Stay (LOS) and assign to categories.
admissions_with_los AS (
    SELECT
        ca.subject_id,
        ca.hadm_id,
        CASE
            WHEN CEIL(DATETIME_DIFF(adm.dischtime, adm.admittime, HOUR) / 24.0) BETWEEN 1 AND 3 THEN '1-3 days'
            WHEN CEIL(DATETIME_DIFF(adm.dischtime, adm.admittime, HOUR) / 24.0) BETWEEN 4 AND 7 THEN '4-7 days'
            ELSE NULL
        END AS los_category
    FROM
        cohort_admissions AS ca
    INNER JOIN
        `physionet-data.mimiciv_3_1_hosp.admissions` AS adm
        ON ca.hadm_id = adm.hadm_id
),

-- 3. Count the number of CT/MRI procedures for each admission in the entire database.
procedure_counts AS (
    SELECT
        proc.hadm_id,
        COUNT(proc.icd_code) AS num_procedures
    FROM
        `physionet-data.mimiciv_3_1_hosp.procedures_icd` AS proc
    INNER JOIN
        `physionet-data.mimiciv_3_1_hosp.d_icd_procedures` AS d_proc
        ON proc.icd_code = d_proc.icd_code AND proc.icd_version = d_proc.icd_version
    WHERE
        d_proc.long_title LIKE '%Computed tomography%'
        OR d_proc.long_title LIKE '%Magnetic resonance imaging%'
    GROUP BY
        proc.hadm_id
)

-- 4. Join the cohort with procedure counts and aggregate the results by LOS category.
SELECT
    al.los_category,
    COUNT(DISTINCT al.subject_id) AS patient_count,
    AVG(COALESCE(pc.num_procedures, 0)) AS mean_procedures_per_admission
FROM
    admissions_with_los AS al
LEFT JOIN
    procedure_counts AS pc
    ON al.hadm_id = pc.hadm_id
WHERE
    al.los_category IS NOT NULL
GROUP BY
    al.los_category
ORDER BY
    al.los_category;