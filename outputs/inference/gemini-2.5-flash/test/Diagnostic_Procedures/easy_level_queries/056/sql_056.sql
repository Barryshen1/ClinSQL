WITH MechanicalSupportProcedures AS (
    -- Step 2: Identify all mechanical circulatory support procedures and their subject_id
    SELECT
        proc.subject_id,
        proc.icd_code
    FROM
        `physionet-data.mimiciv_3_1_hosp.procedures_icd` proc
    JOIN
        `physionet-data.mimiciv_3_1_hosp.d_icd_procedures` dicd
        ON proc.icd_code = dicd.icd_code
        AND proc.icd_version = dicd.icd_version
    WHERE
            LOWER(dicd.long_title) LIKE '%extracorporeal membrane oxygenation%'
        OR  LOWER(dicd.long_title) LIKE '%ecmo%'
        OR  LOWER(dicd.long_title) LIKE '%circulatory assist%'
        OR  LOWER(dicd.long_title) LIKE '%heart assist%'
        OR  LOWER(dicd.long_title) LIKE '%ventricular assist%'
        OR  LOWER(dicd.long_title) LIKE '%intra-aortic balloon%'
        OR  LOWER(dicd.long_title) LIKE '%vad device%'
        OR  LOWER(dicd.long_title) LIKE '%heart pump%'
        OR  LOWER(dicd.long_title) LIKE '%cardiac assist%'
),
PatientDistinctProcedureCounts AS (
    -- Calculate distinct mechanical circulatory support procedures for each patient
    -- in the target cohort. Patients with 0 procedures will correctly have a count of 0.
    SELECT
        p.subject_id,
        COUNT(DISTINCT msp.icd_code) AS distinct_procedure_count
    FROM
        `physionet-data.mimiciv_3_1_hosp.patients` p
    LEFT JOIN MechanicalSupportProcedures msp
        ON p.subject_id = msp.subject_id
    WHERE
        -- Step 1: Filter for the target patient cohort (women 43-53)
        p.gender = 'F'
        AND p.anchor_age BETWEEN 43 AND 53
    GROUP BY
        p.subject_id
)
-- Step 3: Calculate the 25th percentile of distinct procedures from the patient cohort
SELECT
    PERCENTILE_DISC(distinct_procedure_count, 0.25) OVER () AS percentile_25_distinct_procedures
FROM
    PatientDistinctProcedureCounts;