SELECT 
    MAX(DATE_DIFF(adm.dischtime, adm.admittime, DAY)) AS max_los_days
FROM 
    physionet-data.mimiciv_3_1_hosp.admissions AS adm
JOIN 
    physionet-data.mimiciv_3_1_hosp.patients AS pat
    ON adm.subject_id = pat.subject_id
JOIN 
    physionet-data.mimiciv_3_1_hosp.diagnoses_icd AS dx
    ON adm.hadm_id = dx.hadm_id
WHERE 
    pat.gender = 'F'
    AND pat.anchor_age BETWEEN 49 AND 59
    AND dx.seq_num = 1
    AND (
        (dx.icd_version = 9 AND dx.icd_code IN (
            '530.21', '531.00', '531.01', '531.20', '531.21',
            '532.00', '532.01', '532.20', '532.21',
            '533.00', '533.01', '533.20', '533.21',
            '534.00', '534.01'
        ))
        OR
        (dx.icd_version = 10 AND dx.icd_code = 'K92.2')
    );