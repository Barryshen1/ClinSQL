SELECT
    STDDEV_SAMP(DATETIME_DIFF(adm.dischtime, adm.admittime, DAY)) AS sd_hospital_los_days
FROM
    `physionet-data.mimiciv_3_1_hosp.admissions` AS adm
INNER JOIN
    `physionet-data.mimiciv_3_1_hosp.patients` AS pat
    ON adm.subject_id = pat.subject_id
INNER JOIN
    `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` AS dx
    ON adm.hadm_id = dx.hadm_id
WHERE
    -- Filter for patient demographics: men aged 45-55
    pat.gender = 'M'
    AND pat.anchor_age BETWEEN 45 AND 55
    -- Filter for primary diagnosis
    AND dx.seq_num = 1
    -- Filter for hemorrhagic stroke using both ICD-9 and ICD-10 codes
    AND (
        (dx.icd_version = 9 AND SUBSTR(dx.icd_code, 1, 3) IN ('430', '431', '432'))
        OR (dx.icd_version = 10 AND SUBSTR(dx.icd_code, 1, 3) IN ('I60', 'I61', 'I62'))
    );