WITH cohort AS (
    SELECT subject_id
    FROM `physionet-data.mimiciv_3_1_hosp.patients`
    WHERE gender = 'M'
    AND anchor_age BETWEEN 57 AND 67
),
echo_procedures AS (
    SELECT p.subject_id, pr.icd_code, pr.chartdate
    FROM cohort p
    LEFT JOIN `physionet-data.mimiciv_3_1_hosp.procedures_icd` pr
        ON p.subject_id = pr.subject_id
    LEFT JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_procedures` d
        ON pr.icd_code = d.icd_code AND pr.icd_version = d.icd_version
    WHERE d.long_title LIKE '%echocardiogram%'
        OR d.long_title LIKE '%echo%'
        OR d.long_title LIKE '%transthoracic%'
        OR d.long_title LIKE '%transesophageal%'
        OR d.long_title LIKE '%TTE%'
        OR d.long_title LIKE '%TEE%'
),
counts_per_patient AS (
    SELECT subject_id, COUNT(*) AS count_echo
    FROM echo_procedures
    GROUP BY subject_id
)
SELECT APPROX_QUANTILES(count_echo, 100)[OFFSET(75)] AS percentile_75
FROM counts_per_patient;