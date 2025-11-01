SELECT MAX(DATE_DIFF(a.dischtime, a.admittime, DAY)) AS max_los_days
FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
INNER JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` di 
    ON a.subject_id = di.subject_id AND a.hadm_id = di.hadm_id
INNER JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` dd 
    ON di.icd_code = dd.icd_code AND di.icd_version = dd.icd_version
INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` p 
    ON a.subject_id = p.subject_id
WHERE p.anchor_age BETWEEN 49 AND 59
    AND p.gender = 'F'
    AND di.seq_num = 1
    AND di.icd_version = 10
    AND dd.long_title LIKE '%upper gastrointestinal bleed%'
    AND a.dischtime IS NOT NULL;