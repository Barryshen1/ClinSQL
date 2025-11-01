SELECT
    STDDEV(DATETIME_DIFF(adm.dischtime, adm.admittime, DAY)) AS stddev_los_days
FROM
    `physionet-data.mimiciv_3_1_hosp.admissions` AS adm
JOIN
    `physionet-data.mimiciv_3_1_hosp.patients` AS pat
    ON adm.subject_id = pat.subject_id
JOIN
    `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` AS dicd
    ON adm.hadm_id = dicd.hadm_id
WHERE
    pat.gender = 'M'
    AND pat.anchor_age BETWEEN 51 AND 61
    AND dicd.seq_num = 1 -- Filter for primary diagnosis
    AND (
        -- ICD-9 codes for hemorrhagic stroke
        (dicd.icd_version = 9 AND dicd.icd_code IN ('430', '431', '432'))
        OR
        -- ICD-10 codes for hemorrhagic stroke (I60.x, I61.x, I62.x)
        (dicd.icd_version = 10 AND (
            SUBSTR(dicd.icd_code, 1, 3) IN ('I60', 'I61', 'I62')
        ))
    )
    AND adm.admittime IS NOT NULL -- Ensure valid admission time
    AND adm.dischtime IS NOT NULL; -- Ensure valid discharge time for LOS calculation;