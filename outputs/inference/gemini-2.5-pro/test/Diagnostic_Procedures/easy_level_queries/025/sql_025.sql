SELECT
    MIN(num_distinct_procedures) AS min_distinct_mcs_procedures
FROM (
    SELECT
        p.subject_id,
        COUNT(DISTINCT proc.icd_code) AS num_distinct_procedures
    FROM
        `physionet-data.mimiciv_3_1_hosp.patients` AS p
    INNER JOIN
        `physionet-data.mimiciv_3_1_hosp.procedures_icd` AS proc
        ON p.subject_id = proc.subject_id
    INNER JOIN
        `physionet-data.mimiciv_3_1_hosp.d_icd_procedures` AS d_proc
        ON proc.icd_code = d_proc.icd_code AND proc.icd_version = d_proc.icd_version
    WHERE
        -- Filter for the patient cohort: women aged 40-50
        p.gender = 'F'
        AND p.anchor_age BETWEEN 40 AND 50
        -- Filter for mechanical circulatory support procedures using keywords
        AND (
            LOWER(d_proc.long_title) LIKE '%circulatory assist%'
            OR LOWER(d_proc.long_title) LIKE '%balloon pump%'
            OR LOWER(d_proc.long_title) LIKE '%extracorporeal membrane oxygenation%'
            OR LOWER(d_proc.long_title) LIKE '%ecmo%'
            OR LOWER(d_proc.long_title) LIKE '%ventricular assist device%'
            OR LOWER(d_proc.long_title) LIKE '%vad%'
            OR LOWER(d_proc.long_title) LIKE '%impella%'
        )
    GROUP BY
        p.subject_id
) AS patient_procedure_counts;