SELECT
    STDDEV(distinct_procedure_count) AS sd_distinct_procedures
FROM
    (
        SELECT
            p.subject_id,
            COUNT(DISTINCT rpc.icd_code) AS distinct_procedure_count
        FROM
            `physionet-data.mimiciv_3_1_hosp.patients` p
        LEFT JOIN
            `physionet-data.mimiciv_3_1_hosp.procedures_icd` pi
            ON p.subject_id = pi.subject_id
        LEFT JOIN
            (
                SELECT
                    dp.icd_code,
                    dp.icd_version
                FROM
                    `physionet-data.mimiciv_3_1_hosp.d_icd_procedures` dp
                WHERE
                    LOWER(dp.long_title) LIKE '%cardioversion%' -- Covers cardioversion procedures
                    OR LOWER(dp.long_title) LIKE '%catheter ablation%' -- Covers specific catheter ablation
                    OR LOWER(dp.long_title) LIKE '%cardiac ablation%' -- Covers general cardiac ablation (catch-all)
            ) AS rpc
            ON pi.icd_code = rpc.icd_code AND pi.icd_version = rpc.icd_version
        WHERE
            p.gender = 'M'
            AND p.anchor_age BETWEEN 86 AND 96
        GROUP BY
            p.subject_id
    );