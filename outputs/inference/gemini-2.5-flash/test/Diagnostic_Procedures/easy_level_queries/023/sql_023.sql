WITH PatientAdmissions AS (
    -- Step 1 & 2: Identify females aged 82-92 and their hospital admissions
    SELECT
        pat.subject_id,
        adm.hadm_id
    FROM
        `physionet-data.mimiciv_3_1_hosp.patients` pat
    JOIN
        `physionet-data.mimiciv_3_1_hosp.admissions` adm
        ON pat.subject_id = adm.subject_id
    WHERE
        pat.gender = 'F'
        AND pat.anchor_age BETWEEN 82 AND 92
),
CardiacProcedureCodes AS (
    -- Step 3: Identify ICD codes for cardiac procedures
    SELECT
        proc.hadm_id,
        proc.icd_code
    FROM
        `physionet-data.mimiciv_3_1_hosp.procedures_icd` proc
    JOIN
        `physionet-data.mimiciv_3_1_hosp.d_icd_procedures` dicd
        ON proc.icd_code = dicd.icd_code
        AND proc.icd_version = dicd.icd_version
    WHERE
        LOWER(dicd.long_title) LIKE '%cardiac%'
        OR LOWER(dicd.long_title) LIKE '%heart%'
        OR LOWER(dicd.long_title) LIKE '%coronary%'
        OR LOWER(dicd.long_title) LIKE '%valve replacement%'
        OR LOWER(dicd.long_title) LIKE '%angioplasty%'
        OR LOWER(dicd.long_title) LIKE '%stent%'
        OR LOWER(dicd.long_title) LIKE '%bypass%'
        OR LOWER(dicd.long_title) LIKE '%catheterization, cardiac%'
        OR LOWER(dicd.long_title) LIKE '%pacemaker%'
        OR LOWER(dicd.long_title) LIKE '%defibrillator%'
),
DistinctCardiacProceduresPerAdmission AS (
    -- Step 4: Count distinct cardiac procedures for each relevant hospitalization
    -- Use LEFT JOIN to include admissions with 0 cardiac procedures
    SELECT
        pa.hadm_id,
        COUNT(DISTINCT cpc.icd_code) AS distinct_cardiac_procedures_count
    FROM
        PatientAdmissions pa
    LEFT JOIN
        CardiacProcedureCodes cpc
        ON pa.hadm_id = cpc.hadm_id
    GROUP BY
        pa.hadm_id
)
-- Step 5: Calculate the 25th percentile of these counts using BigQuery's aggregate function.
SELECT
    PERCENTILE_CONT(distinct_cardiac_procedures_count, 0.25) AS p25_distinct_cardiac_procedures_per_hospitalization
FROM
    DistinctCardiacProceduresPerAdmission;