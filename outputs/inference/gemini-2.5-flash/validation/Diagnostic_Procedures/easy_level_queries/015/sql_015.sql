WITH CABG_Procedures_Codes AS (
    -- Step 1: Identify all ICD procedure codes related to Coronary Artery Bypass Graft (CABG)
    SELECT
        dicd.icd_code,
        dicd.icd_version
    FROM
        `physionet-data.mimiciv_3_1_hosp.d_icd_procedures` dicd
    WHERE
        LOWER(dicd.long_title) LIKE '%coronary artery bypass graft%'
),
TargetPatients AS (
    -- Step 2: Identify males aged 45-55 (inclusive)
    SELECT
        p.subject_id
    FROM
        `physionet-data.mimiciv_3_1_hosp.patients` p
    WHERE
        p.gender = 'M'
        AND p.anchor_age BETWEEN 45 AND 55
),
PatientCABGCounts AS (
    -- Step 3: For each target patient, count the number of distinct CABG procedure codes they had
    -- Use LEFT JOIN to include patients who might not have any CABG procedures (count will be 0)
    SELECT
        tp.subject_id,
        COUNT(DISTINCT cabg_def.icd_code) AS num_distinct_cabg_procedures
    FROM
        TargetPatients tp
    LEFT JOIN
        `physionet-data.mimiciv_3_1_hosp.procedures_icd` picd
        ON tp.subject_id = picd.subject_id
    LEFT JOIN
        CABG_Procedures_Codes cabg_def
        ON picd.icd_code = cabg_def.icd_code
        AND picd.icd_version = cabg_def.icd_version
    GROUP BY
        tp.subject_id
)
SELECT
    -- Step 4: Calculate the 25th percentile of distinct CABG procedures from the patient counts
    -- Correct BigQuery syntax for PERCENTILE_CONT as an aggregate function
    PERCENTILE_CONT(num_distinct_cabg_procedures, 0.25) AS p25_distinct_cabg_procedures
FROM
    PatientCABGCounts;