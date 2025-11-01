WITH tia_codes AS (
    -- Identify ICD codes for Transient Ischemic Attack (TIA)
    -- ICD-9 codes starting with 435.% and ICD-10 codes starting with G45.%
    SELECT DISTINCT icd_code, icd_version
    FROM `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses`
    WHERE
        (icd_version = 9 AND icd_code LIKE '435.%') OR
        (icd_version = 10 AND icd_code LIKE 'G45.%')
),
ct_mri_proc_codes AS (
    -- Identify ICD codes for CT and MRI procedures
    -- Search for keywords in the long_title of d_icd_procedures
    SELECT DISTINCT icd_code, icd_version
    FROM `physionet-data.mimiciv_3_1_hosp.d_icd_procedures`
    WHERE
        LOWER(long_title) LIKE '%computed tomography%'
        OR LOWER(long_title) LIKE '%ct scan%'
        OR LOWER(long_title) LIKE '%magnetic resonance imaging%'
        OR LOWER(long_title) LIKE '%mri%'
),
eligible_admissions AS (
    -- Select all admissions for female patients aged 50-60 with a TIA diagnosis
    SELECT
        adm.subject_id,
        adm.hadm_id,
        adm.admittime,
        adm.dischtime,
        DATE_DIFF(adm.dischtime, adm.admittime, DAY) AS los_days
    FROM
        `physionet-data.mimiciv_3_1_hosp.admissions` AS adm
    INNER JOIN
        `physionet-data.mimiciv_3_1_hosp.patients` AS pat
        ON adm.subject_id = pat.subject_id
    INNER JOIN
        `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` AS diag
        ON adm.hadm_id = diag.hadm_id
    WHERE
        pat.gender = 'F'
        AND pat.anchor_age BETWEEN 50 AND 60
        AND diag.icd_code IN (SELECT icd_code FROM tia_codes WHERE icd_version = diag.icd_version)
    GROUP BY -- Group by to ensure unique hadm_id for the cohort
        adm.subject_id, adm.hadm_id, adm.admittime, adm.dischtime
),
procedures_per_admission AS (
    -- Count CT/MRI procedures for each eligible admission.
    -- Use LEFT JOIN to include admissions with 0 CT/MRI procedures.
    SELECT
        ea.subject_id,
        ea.hadm_id,
        ea.los_days,
        COUNT(CASE WHEN cmpc.icd_code IS NOT NULL THEN 1 END) AS num_ct_mri_procedures
    FROM
        eligible_admissions AS ea
    LEFT JOIN
        `physionet-data.mimiciv_3_1_hosp.procedures_icd` AS proc
        ON ea.hadm_id = proc.hadm_id
    LEFT JOIN
        ct_mri_proc_codes AS cmpc
        ON proc.icd_code = cmpc.icd_code AND proc.icd_version = cmpc.icd_version
    GROUP BY
        ea.subject_id, ea.hadm_id, ea.los_days
)
-- Final aggregation to calculate patient counts and mean procedures by LOS category
SELECT
    CASE
        WHEN ppa.los_days BETWEEN 1 AND 3 THEN 'LOS 1-3 Days'
        WHEN ppa.los_days BETWEEN 4 AND 7 THEN 'LOS 4-7 Days'
        ELSE 'Other LOS' -- This category will be filtered out by HAVING clause
    END AS los_category,
    COUNT(DISTINCT ppa.subject_id) AS patient_count,
    AVG(ppa.num_ct_mri_procedures) AS mean_ct_mri_procedures_per_admission
FROM
    procedures_per_admission AS ppa
WHERE
    ppa.los_days BETWEEN 1 AND 7 -- Only consider admissions within the specified LOS range
GROUP BY
    los_category
HAVING
    los_category IN ('LOS 1-3 Days', 'LOS 4-7 Days') -- Ensure only the target LOS categories are included
ORDER BY
    los_category;