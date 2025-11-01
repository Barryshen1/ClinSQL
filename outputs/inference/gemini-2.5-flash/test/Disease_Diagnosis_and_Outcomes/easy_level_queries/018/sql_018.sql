SELECT
    STDDEV(DATE_DIFF(adm.dischtime, adm.admittime, DAY)) AS stddev_hospital_los_days
FROM
    `physionet-data.mimiciv_3_1_hosp.admissions` AS adm
JOIN
    `physionet-data.mimiciv_3_1_hosp.patients` AS pat
    ON adm.subject_id = pat.subject_id
JOIN
    `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` AS diag
    ON adm.subject_id = diag.subject_id AND adm.hadm_id = diag.hadm_id
WHERE
    pat.gender = 'M'
    AND pat.anchor_age BETWEEN 45 AND 55
    AND diag.seq_num = 1 -- Primary diagnosis
    AND diag.icd_version = 10 -- Filter for ICD-10 codes specific to hemorrhagic stroke
    AND (
        diag.icd_code LIKE 'I60%' OR -- Nontraumatic subarachnoid hemorrhage
        diag.icd_code LIKE 'I61%' OR -- Nontraumatic intracerebral hemorrhage
        diag.icd_code LIKE 'I62%'    -- Other nontraumatic intracranial hemorrhage
    );