SELECT PERCENTILE_CONT(0.75) WITHIN GROUP (ORDER BY los_days) AS percentile_75
FROM (
    SELECT
        TIMESTAMP_DIFF(a.dischtime, a.admittime, DAY) AS los_days
    FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
    JOIN `physionet-data.mimiciv_3_1_hosp.patients` p ON a.subject_id = p.subject_id
    JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d ON a.hadm_id = d.hadm_id
    WHERE
        d.seq_num = 1
        AND d.icd_version = 10
        AND d.icd_code LIKE 'N17%'
        AND p.gender = 'M'
        AND (p.anchor_age + EXTRACT(YEAR FROM a.admittime) - p.anchor_year) BETWEEN 37 AND 47
) subquery;