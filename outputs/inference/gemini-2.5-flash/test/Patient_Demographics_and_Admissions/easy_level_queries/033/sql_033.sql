SELECT
    STDDEV(DATETIME_DIFF(adm.dischtime, adm.admittime, DAY)) AS stddev_los_days
FROM
    `physionet-data.mimiciv_3_1_hosp`.admissions adm
JOIN
    `physionet-data.mimiciv_3_1_hosp`.patients pat
    ON adm.subject_id = pat.subject_id
WHERE
    pat.gender = 'M'
    AND pat.anchor_age BETWEEN 44 AND 54
    AND EXISTS (
        SELECT 1
        FROM `physionet-data.mimiciv_3_1_hosp`.diagnoses_icd dicd
        WHERE
            dicd.subject_id = adm.subject_id
            AND dicd.hadm_id = adm.hadm_id
            AND (
                -- ICD-9 codes for dialysis encounter/type
                (dicd.icd_version = 9 AND dicd.icd_code IN ('V560', 'V561', 'V562'))
                OR
                -- ICD-10 code for dependence on renal dialysis
                (dicd.icd_version = 10 AND dicd.icd_code = 'Z992')
            )
    );