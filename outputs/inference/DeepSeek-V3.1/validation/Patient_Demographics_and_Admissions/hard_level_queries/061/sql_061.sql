SELECT COUNT(DISTINCT adm.hadm_id) AS total_admissions
FROM `physionet-data.mimiciv_3_1_hosp.patients` pat
INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` adm
    ON pat.subject_id = adm.subject_id
INNER JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` diag
    ON adm.hadm_id = diag.hadm_id
WHERE pat.gender = 'F'
    AND pat.anchor_age BETWEEN 63 AND 73
    AND adm.insurance = 'Medicare'
    AND adm.admission_location = 'TRANSFER FROM HOSPITAL'
    AND diag.seq_num = 1  -- principal diagnosis
    AND (
        (diag.icd_version = 10 AND diag.icd_code LIKE 'I48%')  -- ICD-10 codes for atrial fibrillation
        OR
        (diag.icd_version = 9 AND diag.icd_code LIKE '427.3%') -- ICD-9 code for atrial fibrillation
    );