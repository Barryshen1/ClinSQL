SELECT COUNT(DISTINCT adm.hadm_id) AS total_index_admissions
FROM `physionet-data.mimiciv_3_1_hosp.admissions` adm
INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` pat
    ON adm.subject_id = pat.subject_id
INNER JOIN (
    SELECT hadm_id, icd_code
    FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd`
    WHERE seq_num = 1
        AND icd_version = 10
        AND icd_code = 'K81.0'
) diag
    ON adm.hadm_id = diag.hadm_id
WHERE pat.anchor_age BETWEEN 38 AND 48
    AND pat.gender = 'F'
    AND adm.admission_location = 'EMERGENCY ROOM'
    AND adm.insurance = 'Medicare';