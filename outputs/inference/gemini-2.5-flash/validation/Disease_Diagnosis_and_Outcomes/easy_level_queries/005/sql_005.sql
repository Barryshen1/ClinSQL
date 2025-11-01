SELECT
    PERCENTILE_CONT(DATETIME_DIFF(a.dischtime, a.admittime, DAY), 0.5) OVER() AS median_hospital_los_days
FROM
    `physionet-data.mimiciv_3_1_hosp.patients` p
INNER JOIN
    `physionet-data.mimiciv_3_1_hosp.admissions` a
    ON p.subject_id = a.subject_id
INNER JOIN
    `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` di
    ON a.hadm_id = di.hadm_id
WHERE
    p.gender = 'F'
    AND p.anchor_age BETWEEN 59 AND 69
    AND di.seq_num = 1 -- Primary diagnosis
    AND (
        (di.icd_version = 9 AND di.icd_code IN ('43301', '43311', '43321', '43331', '43381', '43391', '43401', '43411', '43491'))
        OR
        (di.icd_version = 10 AND di.icd_code LIKE 'I63%')
    )
;