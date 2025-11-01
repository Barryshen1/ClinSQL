WITH
-- CTE to identify all ICD codes related to valve repair or replacement
ValveProcedureCodes AS (
    SELECT
        icd_code,
        icd_version
    FROM
        `physionet-data.mimiciv_3_1_hosp.d_icd_procedures`
    WHERE
        LOWER(long_title) LIKE '%valve replacement%'
        OR LOWER(long_title) LIKE '%valve repair%'
        OR LOWER(long_title) LIKE '%valvuloplasty%'
),

-- CTE to count the number of distinct valve procedures for each hospitalization
-- belonging to the specified patient cohort (males, age 52-62)
ProcedureCountsPerAdmission AS (
    SELECT
        -- Count the distinct valve procedure codes for each admission.
        -- Due to the LEFT JOINs, if an admission has no matching procedures,
        -- vpc.icd_code will be NULL, and the count will correctly be 0.
        COUNT(DISTINCT vpc.icd_code) AS num_distinct_procedures
    FROM
        `physionet-data.mimiciv_3_1_hosp.patients` AS p
    -- Get all hospitalizations for the patients
    INNER JOIN
        `physionet-data.mimiciv_3_1_hosp.admissions` AS adm
        ON p.subject_id = adm.subject_id
    -- Left join to procedures to include admissions that have no procedures
    LEFT JOIN
        `physionet-data.mimiciv_3_1_hosp.procedures_icd` AS pro
        ON adm.hadm_id = pro.hadm_id
    -- Left join to our filtered list of valve codes to identify relevant procedures
    LEFT JOIN
        ValveProcedureCodes AS vpc
        ON pro.icd_code = vpc.icd_code AND pro.icd_version = vpc.icd_version
    WHERE
        p.gender = 'M'
        AND p.anchor_age BETWEEN 52 AND 62
    GROUP BY
        adm.hadm_id
)

-- Final step: Calculate the interquartile range from the per-admission counts
SELECT
    -- APPROX_QUANTILES(..., 4) returns an array: [min, 25th, 50th, 75th, max].
    -- IQR is the 75th percentile (at offset 3) minus the 25th percentile (at offset 1).
    APPROX_QUANTILES(num_distinct_procedures, 4)[OFFSET(3)] - APPROX_QUANTILES(num_distinct_procedures, 4)[OFFSET(1)] AS iqr_distinct_valve_procedures
FROM
    ProcedureCountsPerAdmission;