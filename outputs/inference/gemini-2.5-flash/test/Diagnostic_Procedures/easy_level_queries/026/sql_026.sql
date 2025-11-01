SELECT
    -- Calculate the 25th percentile (Q1) of distinct procedures per patient
    PERCENTILE_CONT(num_distinct_procedures, 0.25) OVER() AS q1,
    -- Calculate the 75th percentile (Q3) of distinct procedures per patient
    PERCENTILE_CONT(num_distinct_procedures, 0.75) OVER() AS q3,
    -- Calculate the Interquartile Range (IQR = Q3 - Q1)
    PERCENTILE_CONT(num_distinct_procedures, 0.75) OVER() - PERCENTILE_CONT(num_distinct_procedures, 0.25) OVER() AS iqr
FROM
    (
        SELECT
            pp.subject_id,
            COUNT(DISTINCT pp.icd_code) AS num_distinct_procedures
        FROM
            `physionet-data.mimiciv_3_1_hosp.patients` p
        INNER JOIN
            `physionet-data.mimiciv_3_1_hosp.procedures_icd` pp
            ON p.subject_id = pp.subject_id
        INNER JOIN
            `physionet-data.mimiciv_3_1_hosp.d_icd_procedures` dicd
            ON pp.icd_code = dicd.icd_code AND pp.icd_version = dicd.icd_version
        WHERE
            p.gender = 'M'
            AND p.anchor_age BETWEEN 75 AND 85
            AND (
                -- Identify catheter ablation procedures
                LOWER(dicd.long_title) LIKE '%ablat%' AND LOWER(dicd.long_title) LIKE '%catheter%'
                -- Identify cardioversion procedures
                OR LOWER(dicd.long_title) LIKE '%cardioversion%'
            )
        GROUP BY
            pp.subject_id
    ) AS DistinctProceduresPerPatient
LIMIT 1; -- We only need one row containing the aggregated IQR result;