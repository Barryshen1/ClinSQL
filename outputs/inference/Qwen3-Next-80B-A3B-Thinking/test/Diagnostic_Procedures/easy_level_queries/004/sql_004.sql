WITH patient_cabg_counts AS (
    SELECT
        p.subject_id,
        COUNT(d.long_title) AS cabg_count
    FROM
        `physionet-data.mimiciv_3_1_hosp.patients` p
    LEFT JOIN
        `physionet-data.mimiciv_3_1_hosp.procedures_icd` pr
        ON p.subject_id = pr.subject_id
    LEFT JOIN
        `physionet-data.mimiciv_3_1_hosp.d_icd_procedures` d
        ON pr.icd_code = d.icd_code
        AND pr.icd_version = d.icd_version
        AND LOWER(d.long_title) LIKE '%cabg%'
    WHERE
        p.gender = 'F'
        AND p.anchor_age BETWEEN 41 AND 51
    GROUP BY
        p.subject_id
)
SELECT
    STDDEV(cabg_count) AS std_dev_cabg
FROM
    patient_cabg_counts;