SELECT
    MIN(TIMESTAMP_DIFF(ad.dischtime, ad.admittime, DAY)) AS min_hospital_los_days
FROM
    `physionet-data.mimiciv_3_1_hosp.admissions` AS ad
JOIN
    `physionet-data.mimiciv_3_1_hosp.patients` AS p
    ON ad.subject_id = p.subject_id
JOIN
    `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` AS dicd
    ON ad.hadm_id = dicd.hadm_id
WHERE
    p.gender = 'F'
    AND p.anchor_age BETWEEN 88 AND 98
    AND dicd.seq_num = 1 -- Filter for primary diagnosis
    AND (
        -- ICD-9 codes for pneumonia (480-486 range)
        (dicd.icd_version = 9 AND SUBSTR(dicd.icd_code, 1, 3) BETWEEN '480' AND '486')
        OR
        -- ICD-10 codes for pneumonia (J10-J18 range)
        (dicd.icd_version = 10 AND SUBSTR(dicd.icd_code, 1, 3) BETWEEN 'J10' AND 'J18')
    );