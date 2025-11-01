SELECT COUNT(DISTINCT adm.hadm_id) AS total_admissions
FROM `physionet-data.mimiciv_3_1_hosp.patients` pt
INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` adm
    ON pt.subject_id = adm.subject_id
INNER JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` diag
    ON adm.subject_id = diag.subject_id AND adm.hadm_id = diag.hadm_id
WHERE pt.gender = 'F'
    AND pt.anchor_age BETWEEN 62 AND 72
    AND adm.admission_location LIKE '%EMERGENCY ROOM%'  -- Common value for ER
    AND adm.insurance = 'Medicare'
    AND diag.seq_num = 1  -- Principal diagnosis
    AND (
        (diag.icd_version = 9 AND diag.icd_code = '780.2') 
        OR 
        (diag.icd_version = 10 AND diag.icd_code = 'R55')
    );