WITH PatientLOS AS (
    SELECT
        adm.subject_id,
        adm.hadm_id,
        DATETIME_DIFF(adm.dischtime, adm.admittime, DAY) AS los_days
    FROM
        `physionet-data.mimiciv_3_1_hosp.admissions` AS adm
    INNER JOIN
        `physionet-data.mimiciv_3_1_hosp.patients` AS pat
        ON adm.subject_id = pat.subject_id
    INNER JOIN
        `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` AS di
        ON adm.hadm_id = di.hadm_id
    WHERE
        pat.gender = 'F'
        AND pat.anchor_age BETWEEN 71 AND 81
        AND di.seq_num = 1 -- Primary diagnosis
        AND (
               (di.icd_version = 9 AND di.icd_code IN ('43301', '43311', '43321', '43331', '43381', '43391', '43401', '43411', '43491', '436'))
            OR (di.icd_version = 10 AND di.icd_code LIKE 'I63%')
        )
)
SELECT
    PERCENTILE_CONT(los_days, 0.25) OVER() AS Q1_hospital_los_days,
    PERCENTILE_CONT(los_days, 0.75) OVER() AS Q3_hospital_los_days,
    PERCENTILE_CONT(los_days, 0.75) OVER() - PERCENTILE_CONT(los_days, 0.25) OVER() AS IQR_hospital_los_days
FROM
    PatientLOS
LIMIT 1;