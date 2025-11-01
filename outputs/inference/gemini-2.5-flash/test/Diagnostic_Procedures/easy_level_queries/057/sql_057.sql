WITH EligiblePatients AS (
    -- Step 1: Identify eligible female patients aged 64-74
    SELECT
        p.subject_id
    FROM
        `physionet-data.mimiciv_3_1_hosp.patients` p
    WHERE
        p.gender = 'F'
        AND p.anchor_age BETWEEN 64 AND 74
),
CardiacCathProcedures AS (
    -- Step 2: Identify diagnostic cardiac catheterization procedures
    SELECT
        pr.subject_id,
        pr.chartdate,
        pr.icd_code,
        pr.icd_version,
        dicd.long_title
    FROM
        `physionet-data.mimiciv_3_1_hosp.procedures_icd` pr
    INNER JOIN
        `physionet-data.mimiciv_3_1_hosp.d_icd_procedures` dicd
        ON pr.icd_code = dicd.icd_code AND pr.icd_version = dicd.icd_version
    WHERE
        (
            -- Common ICD-9 codes for diagnostic cardiac catheterization
            (pr.icd_version = 9 AND pr.icd_code IN ('3721', '3722', '3723', '3726', '3727', '3728'))
            -- General terms often associated with diagnostic cardiac cath in titles (applies to both ICD-9 and ICD-10)
            OR dicd.long_title LIKE '%Cardiac Catheterization%'
            OR dicd.long_title LIKE '%Coronary Arteriography%'
        )
),
PatientProcedureCounts AS (
    -- Step 3 & 4: Count distinct diagnostic cardiac cath procedures per eligible patient.
    -- Use LEFT JOIN to include patients who had zero procedures.
    -- Count distinct chartdates to represent distinct procedure events.
    SELECT
        ep.subject_id,
        COUNT(DISTINCT ccp.chartdate) AS num_procedures
    FROM
        EligiblePatients ep
    LEFT JOIN
        CardiacCathProcedures ccp
        ON ep.subject_id = ccp.subject_id
    GROUP BY
        ep.subject_id
)
-- Step 5: Find the minimum number of procedures among these patients
SELECT
    MIN(num_procedures) AS min_diagnostic_cardiac_catheterization_procedures_per_patient
FROM
    PatientProcedureCounts;