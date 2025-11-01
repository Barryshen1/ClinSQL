SELECT
    PERCENTILE_CONT(PatientEchoCounts.distinct_echo_count, 0.25) OVER() AS p25_distinct_echo_procedures
FROM
    (
        SELECT
            p.subject_id,
            -- COUNT(DISTINCT procs.icd_code) counts distinct ICD codes for echo procedures.
            -- If a patient has no matching echo procedures, procs.icd_code will be NULL,
            -- and COUNT(DISTINCT NULL) evaluates to 0, which is correct for these patients.
            COUNT(DISTINCT procs.icd_code) AS distinct_echo_count
        FROM
            `physionet-data.mimiciv_3_1_hosp.patients` p
        LEFT JOIN
            (
                SELECT
                    pi.subject_id,
                    pi.icd_code,
                    pi.icd_version
                FROM
                    `physionet-data.mimiciv_3_1_hosp.procedures_icd` pi
                JOIN
                    `physionet-data.mimiciv_3_1_hosp.d_icd_procedures` dp
                    ON pi.icd_code = dp.icd_code AND pi.icd_version = dp.icd_version
                WHERE
                    -- Filter for echocardiography-related procedures based on description or specific ICD-9 codes
                    dp.long_title LIKE '%echocardiography%'
                    OR dp.long_title LIKE '%ultrasound of heart%'
                    OR (pi.icd_version = 9 AND pi.icd_code LIKE '37.2%')
            ) AS procs
            ON p.subject_id = procs.subject_id
        WHERE
            p.gender = 'F'
            AND p.anchor_age BETWEEN 88 AND 98
        GROUP BY
            p.subject_id
    ) AS PatientEchoCounts;