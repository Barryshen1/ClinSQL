SELECT
    STDDEV(distinct_ecg_procedures_count) AS stddev_distinct_ecg_codes
FROM
    (
        -- Step 3 & 4: Count distinct ECG/telemetry procedures for each target patient
        SELECT
            tp.subject_id,
            COUNT(DISTINCT ep.icd_code) AS distinct_ecg_procedures_count
        FROM
            -- Step 1: Identify target patient cohort
            (
                SELECT
                    p.subject_id
                FROM
                    `physionet-data.mimiciv_3_1_hosp.patients` AS p
                WHERE
                    p.gender = 'M'
                    AND p.anchor_age BETWEEN 81 AND 91
            ) AS tp
        LEFT JOIN
            -- Step 2: Identify all ECG/telemetry related procedures
            (
                SELECT
                    proc.subject_id,
                    proc.icd_code
                FROM
                    `physionet-data.mimiciv_3_1_hosp.procedures_icd` AS proc
                INNER JOIN
                    `physionet-data.mimiciv_3_1_hosp.d_icd_procedures` AS d_proc
                    ON proc.icd_code = d_proc.icd_code
                    AND proc.icd_version = d_proc.icd_version
                WHERE
                    LOWER(d_proc.long_title) LIKE '%ecg%'
                    OR LOWER(d_proc.long_title) LIKE '%electrocardiogram%'
                    OR LOWER(d_proc.long_title) LIKE '%ekg%'
                    OR LOWER(d_proc.long_title) LIKE '%telemetry%'
                    OR LOWER(d_proc.long_title) LIKE '%cardiac monitor%'
            ) AS ep
            ON tp.subject_id = ep.subject_id
        GROUP BY
            tp.subject_id
    ) AS patient_ecg_counts;