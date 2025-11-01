SELECT COUNT(DISTINCT a.hadm_id)
FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` p ON a.subject_id = p.subject_id
INNER JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` di ON a.hadm_id = di.hadm_id
INNER JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` dicd ON di.icd_code = dicd.icd_code AND di.icd_version = dicd.icd_version
WHERE p.gender = 'M'
AND a.insurance = 'Medicare'
AND p.anchor_age BETWEEN 72 AND 82
AND a.admission_location = 'TRANSFER FROM HOSPITAL'
AND di.seq_num = 1  
AND dicd.long_title LIKE '%Unstable angina%'  
AND a.dischtime IS NOT NULL;