SELECT
    MAX(distinct_echo_procedures_per_admission) AS max_distinct_echocardiography_procedures
FROM (
    SELECT
        pa.subject_id,
        ad.hadm_id,
        COUNT(DISTINCT pr.icd_code) AS distinct_echo_procedures_per_admission
    FROM
        `physionet-data.mimiciv_3_1_hosp.patients` pa
    INNER JOIN
        `physionet-data.mimiciv_3_1_hosp.admissions` ad
        ON pa.subject_id = ad.subject_id
    INNER JOIN
        `physionet-data.mimiciv_3_1_hosp.procedures_icd` pr
        ON ad.hadm_id = pr.hadm_id
    INNER JOIN
        `physionet-data.mimiciv_3_1_hosp.d_icd_procedures` dp
        ON pr.icd_code = dp.icd_code AND pr.icd_version = dp.icd_version
    WHERE
        pa.gender = 'F'
        AND pa.anchor_age BETWEEN 81 AND 91
        AND (
            LOWER(dp.long_title) LIKE '%echocardio%'
            OR LOWER(dp.long_title) LIKE '%ultrasonography of heart%'
            OR LOWER(dp.long_title) LIKE '%ultrasound of heart%'
        )
    GROUP BY
        pa.subject_id,
        ad.hadm_id
) AS distinct_echo_counts_per_admission;