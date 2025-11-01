WITH TargetAdmissions AS (
    -- Select all hospital admissions for female patients aged 75-85
    SELECT
        ad.hadm_id
    FROM
        `physionet-data.mimiciv_3_1_hosp.patients` AS p
    JOIN
        `physionet-data.mimiciv_3_1_hosp.admissions` AS ad
        ON p.subject_id = ad.subject_id
    WHERE
        p.gender = 'F'
        AND p.anchor_age BETWEEN 75 AND 85
),
ECGTelemetryProcedures AS (
    -- Identify ICD codes corresponding to ECG/telemetry procedures based on long_title keywords
    SELECT DISTINCT
        pr.hadm_id,
        pr.icd_code
    FROM
        `physionet-data.mimiciv_3_1_hosp.procedures_icd` AS pr
    JOIN
        `physionet-data.mimiciv_3_1_hosp.d_icd_procedures` AS dip
        ON pr.icd_code = dip.icd_code
        AND pr.icd_version = dip.icd_version
    WHERE
        LOWER(dip.long_title) LIKE '%electrocardiogram%'
        OR LOWER(dip.long_title) LIKE '%ekg%'
        OR LOWER(dip.long_title) LIKE '%cardiac monitoring%'
        OR LOWER(dip.long_title) LIKE '%telemetry%'
        OR LOWER(dip.long_title) LIKE '%rhythm monitoring%'
        OR LOWER(dip.long_title) LIKE '%arrhythmia monitoring%'
        -- Explicitly include common ICD-9 codes for these procedures
        OR (pr.icd_version = 9 AND pr.icd_code IN ('8952', '8954'))
),
DistinctProcedureCountsPerAdmission AS (
    -- Count distinct ECG/telemetry procedures for each hospitalization in the target group
    -- A LEFT JOIN ensures admissions with 0 such procedures are included.
    SELECT
        ta.hadm_id,
        COUNT(DISTINCT etp.icd_code) AS distinct_ecg_procedures_count
    FROM
        TargetAdmissions AS ta
    LEFT JOIN
        ECGTelemetryProcedures AS etp
        ON ta.hadm_id = etp.hadm_id
    GROUP BY
        ta.hadm_id
)
-- Calculate the 75th percentile of the distinct procedure counts
SELECT
    PERCENTILE_CONT(distinct_ecg_procedures_count, 0.75) OVER() AS p75_distinct_ecg_telemetry_procedures
FROM
    DistinctProcedureCountsPerAdmission;