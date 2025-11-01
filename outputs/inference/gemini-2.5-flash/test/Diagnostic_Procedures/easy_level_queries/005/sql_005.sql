WITH patient_distinct_echo_procedures AS (
    SELECT
        tp.subject_id,
        COUNT(DISTINCT ep.icd_code) AS distinct_echo_procedures_count
    FROM
        `physionet-data.mimiciv_3_1_hosp.patients` AS tp
    LEFT JOIN (
        SELECT
            proc.subject_id,
            proc.icd_code,
            proc.icd_version
        FROM
            `physionet-data.mimiciv_3_1_hosp.procedures_icd` AS proc
        JOIN
            `physionet-data.mimiciv_3_1_hosp.d_icd_procedures` AS dicd
            ON proc.icd_code = dicd.icd_code
            AND proc.icd_version = dicd.icd_version
        WHERE
            LOWER(dicd.long_title) LIKE '%echocardiography%'
    ) AS ep
        ON tp.subject_id = ep.subject_id
    WHERE
        tp.gender = 'M'
        AND tp.anchor_age BETWEEN 57 AND 67
    GROUP BY
        tp.subject_id
)
SELECT
    PERCENTILE_CONT(0.75) WITHIN GROUP (ORDER BY distinct_echo_procedures_count) OVER () AS q75_distinct_echo_procedures
FROM
    patient_distinct_echo_procedures;