SELECT COUNT(DISTINCT adm.hadm_id) AS admission_count
FROM `physionet-data.mimiciv_3_1_hosp.admissions` adm
INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` pat
    ON adm.subject_id = pat.subject_id
INNER JOIN (
    SELECT subject_id, hadm_id, icd_code, icd_version
    FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd`
    WHERE seq_num = 1  -- principal diagnosis
) diag
    ON adm.hadm_id = diag.hadm_id AND adm.subject_id = diag.subject_id
WHERE pat.gender = 'M'
    AND pat.anchor_age BETWEEN 90 AND 100
    AND adm.admission_type = 'TRANSFER'
    AND (
        (diag.icd_version = 9 AND diag.icd_code = '585.6') OR
        (diag.icd_version = 10 AND diag.icd_code = 'N18.6')
    );