SELECT
    MAX(distinct_echo_procedures) AS max_distinct_echocardiography_procedures_per_admission
FROM (
    SELECT
        pa.subject_id,
        pr.hadm_id,
        COUNT(DISTINCT pr.icd_code) AS distinct_echo_procedures
    FROM
        `physionet-data.mimiciv_3_1_hosp.patients` AS pa
    JOIN
        `physionet-data.mimiciv_3_1_hosp.procedures_icd` AS pr
        ON pa.subject_id = pr.subject_id
    JOIN
        `physionet-data.mimiciv_3_1_hosp.d_icd_procedures` AS d_pr
        ON pr.icd_code = d_pr.icd_code AND pr.icd_version = d_pr.icd_version
    WHERE
        pa.gender = 'M'
        AND pa.anchor_age BETWEEN 84 AND 94
        AND LOWER(d_pr.long_title) LIKE '%echocardiogra%'
    GROUP BY
        pa.subject_id,
        pr.hadm_id
) AS admission_procedure_counts;