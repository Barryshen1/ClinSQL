WITH eligible_admissions AS (
    SELECT
        a.hadm_id,
        TIMESTAMP_DIFF(a.dischtime, a.admittime, DAY) AS los_days
    FROM
        `physionet-data.mimiciv_3_1_hosp.patients` p
    INNER JOIN
        `physionet-data.mimiciv_3_1_hosp.admissions` a
        ON p.subject_id = a.subject_id
    INNER JOIN
        `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
        ON a.subject_id = d.subject_id
        AND a.hadm_id = d.hadm_id
    WHERE
        p.gender = 'M'
        AND p.anchor_age BETWEEN 45 AND 55
        AND a.dischtime IS NOT NULL
        AND d.seq_num = 1
        AND (d.icd_code LIKE '430%' OR d.icd_code LIKE '431%')
)
SELECT
    STDDEV(los_days) AS std_los
FROM
    eligible_admissions;