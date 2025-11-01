SELECT
    PERCENTILE_CONT(hospital_los_days, 0.75) OVER() - PERCENTILE_CONT(hospital_los_days, 0.25) OVER() AS hospital_los_iqr
FROM
    (
        SELECT DISTINCT
            adm.hadm_id,
            DATE_DIFF(adm.dischtime, adm.admittime, DAY) AS hospital_los_days
        FROM
            `physionet-data.mimiciv_3_1_hosp.patients` p
        JOIN
            `physionet-data.mimiciv_3_1_hosp.admissions` adm
            ON p.subject_id = adm.subject_id
        JOIN
            `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` dicd
            ON adm.hadm_id = dicd.hadm_id
        WHERE
            p.gender = 'F'
            AND p.anchor_age BETWEEN 40 AND 50
            AND dicd.seq_num = 1 -- Primary diagnosis
            AND (
                (dicd.icd_version = 9 AND dicd.icd_code IN ('99591', '99592', '78552'))
                OR (dicd.icd_version = 10 AND (dicd.icd_code LIKE 'A41%' OR dicd.icd_code LIKE 'R652%'))
            )
            AND adm.dischtime IS NOT NULL
            AND adm.admittime IS NOT NULL
            AND adm.dischtime > adm.admittime
    ) AS SepsisAdmissions
LIMIT 1;