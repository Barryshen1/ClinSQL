WITH hf_patients AS (
    SELECT DISTINCT p.subject_id, p.gender, p.anchor_age,
           a.hadm_id, a.admittime, a.dischtime, a.hospital_expire_flag
    FROM `physionet-data.mimiciv_3_1_hosp.patients` p
    INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a
        ON p.subject_id = a.subject_id
    INNER JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` di
        ON a.hadm_id = di.hadm_id
    WHERE p.gender = 'M'
        AND p.anchor_age BETWEEN 43 AND 53
        AND (
            (di.icd_version = 10 AND di.icd_code LIKE 'I50%') OR
            (di.icd_version = 9 AND di.icd_code LIKE '428%')
        )
),
los_data AS (
    SELECT *,
        DATE_DIFF(dischtime, admittime, DAY) AS los,
        NTILE(4) OVER (ORDER BY DATE_DIFF(dischtime, admittime, DAY)) AS los_quartile
    FROM hf_patients
)
SELECT los_quartile,
    COUNT(*) AS num_patients,
    SUM(hospital_expire_flag) AS deaths,
    ROUND(100 * AVG(hospital_expire_flag), 2) AS mortality_percent
FROM los_data
GROUP BY los_quartile
ORDER BY los_quartile;