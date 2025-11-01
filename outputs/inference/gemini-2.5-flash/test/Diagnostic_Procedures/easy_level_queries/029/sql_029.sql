WITH PacemakerICDCodes AS (
    -- Step 2: Identify relevant ICD codes for pacemaker/ICD procedures
    SELECT DISTINCT icd_code, icd_version
    FROM `physionet-data.mimiciv_3_1_hosp.d_icd_procedures`
    WHERE
        -- Look for device types
        (
            LOWER(long_title) LIKE '%pacemaker%' OR
            LOWER(long_title) LIKE '%defibrillator%' OR
            LOWER(long_title) LIKE '%cardioverter%'
        )
        AND
        -- Look for procedural actions
        (
            LOWER(long_title) LIKE '%insert%' OR
            LOWER(long_title) LIKE '%implant%' OR
            LOWER(long_title) LIKE '%replac%' OR  -- covers replace, replacement
            LOWER(long_title) LIKE '%change%' OR
            LOWER(long_title) LIKE '%remov%' OR   -- covers remove, removal
            LOWER(long_title) LIKE '%revis%' OR   -- covers revise, revision
            LOWER(long_title) LIKE '%reposition%'
        )
),
PatientProcedureCounts AS (
    -- Step 1 & 3 & 4: Filter patients, link procedures, and count distinct procedures per patient
    SELECT
        pa.subject_id,
        COUNT(DISTINCT pp_icd.icd_code) AS distinct_procedure_count
    FROM
        `physionet-data.mimiciv_3_1_hosp.patients` pa
    JOIN
        `physionet-data.mimiciv_3_1_hosp.admissions` adm
        ON pa.subject_id = adm.subject_id
    JOIN
        `physionet-data.mimiciv_3_1_hosp.procedures_icd` pp_icd
        ON adm.hadm_id = pp_icd.hadm_id AND pa.subject_id = pp_icd.subject_id
    JOIN
        PacemakerICDCodes pic
        ON pp_icd.icd_code = pic.icd_code AND pp_icd.icd_version = pic.icd_version
    WHERE
        pa.gender = 'M'
        AND pa.anchor_age BETWEEN 78 AND 88
    GROUP BY
        pa.subject_id
)
-- Step 5: Calculate the 25th percentile of distinct procedure counts
SELECT
    APPROX_QUANTILES(distinct_procedure_count, 4)[OFFSET(1)] AS p25_distinct_pacemaker_icd_procedures
FROM
    PatientProcedureCounts;