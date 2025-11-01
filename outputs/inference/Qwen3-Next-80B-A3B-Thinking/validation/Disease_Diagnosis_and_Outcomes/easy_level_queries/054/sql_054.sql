SELECT STDDEV(los_days) AS std_dev_los
FROM (
    SELECT
        DATE_DIFF(a.dischtime, a.admittime, DAY) AS los_days
    FROM `physionet-data.mimiciv_3_1_hosp.patients` p
    JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a
        ON p.subject_id = a.subject_id
    JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
        ON a.hadm_id = d.hadm_id
    WHERE
        p.gender = 'M'
        AND p.anchor_age BETWEEN 51 AND 61
        AND d.seq_num = 1
        AND (
            (d.icd_version = 9 AND d.icd_code BETWEEN '430' AND '432')
            OR
            (d.icd_version = 10 AND (d.icd_code LIKE 'I60%' OR d.icd_code LIKE 'I61%' OR d.icd_code LIKE 'I62%'))
        )
) subquery;