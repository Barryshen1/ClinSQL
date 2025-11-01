SELECT
    MAX(DATETIME_DIFF(adm.dischtime, adm.admittime, DAY)) AS max_hospital_los_days
FROM
    `physionet-data.mimiciv_3_1_hosp.admissions` adm
JOIN
    `physionet-data.mimiciv_3_1_hosp.patients` pat
    ON adm.subject_id = pat.subject_id
JOIN
    `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` di
    ON adm.subject_id = di.subject_id AND adm.hadm_id = di.hadm_id
WHERE
    pat.gender = 'M'
    AND pat.anchor_age BETWEEN 84 AND 94
    AND adm.dischtime IS NOT NULL -- Ensure discharge time is recorded for LOS calculation
    AND di.seq_num = 1 -- Primary diagnosis as per clinical question "primary ischemic stroke"
    AND (
        -- ICD-9 codes for ischemic stroke
        (di.icd_version = 9 AND (di.icd_code LIKE '434.%1' OR di.icd_code = '436'))
        OR
        -- ICD-10 codes for ischemic stroke
        (di.icd_version = 10 AND di.icd_code LIKE 'I63%')
    );