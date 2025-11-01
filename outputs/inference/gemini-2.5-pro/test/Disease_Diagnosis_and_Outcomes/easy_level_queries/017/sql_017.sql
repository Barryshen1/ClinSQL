SELECT
    MAX(DATETIME_DIFF(adm.dischtime, adm.admittime, DAY)) AS max_hospital_los_days
FROM
    `physionet-data.mimiciv_3_1_hosp.admissions` AS adm
INNER JOIN
    `physionet-data.mimiciv_3_1_hosp.patients` AS pat
    ON adm.subject_id = pat.subject_id
INNER JOIN
    `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` AS dx
    ON adm.hadm_id = dx.hadm_id
WHERE
    -- Filter for male patients aged 84-94
    pat.gender = 'M'
    AND pat.anchor_age BETWEEN 84 AND 94
    -- Filter for primary diagnosis (seq_num = 1)
    AND dx.seq_num = 1
    -- Filter for ICD codes corresponding to ischemic stroke
    AND (
        (dx.icd_version = 9 AND (dx.icd_code LIKE '433%' OR dx.icd_code LIKE '434%'))
        OR
        (dx.icd_version = 10 AND dx.icd_code LIKE 'I63%')
    );