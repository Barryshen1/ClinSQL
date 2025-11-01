SELECT 
    STDDEV(DATE_DIFF(adm.dischtime, adm.admittime, DAY)) AS std_dev_los
FROM 
    `physionet-data.mimiciv_3_1_hosp.admissions` adm
INNER JOIN 
    `physionet-data.mimiciv_3_1_hosp.patients` p 
        ON adm.subject_id = p.subject_id
INNER JOIN 
    `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d 
        ON adm.hadm_id = d.hadm_id
WHERE 
    p.gender = 'M'
    AND p.anchor_age BETWEEN 77 AND 87
    AND d.icd_code IN ('456.2', '530.7', '531.7', '532.7', '533.7', '534.7')
    AND d.seq_num = 1;