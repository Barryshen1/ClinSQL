SELECT COUNT(DISTINCT adm.hadm_id) AS total_admissions
FROM `physionet-data.mimiciv_3_1_hosp.patients` p
INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` adm
    ON p.subject_id = adm.subject_id
INNER JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` diag
    ON adm.hadm_id = diag.hadm_id
INNER JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` d
    ON diag.icd_code = d.icd_code AND diag.icd_version = d.icd_version
WHERE
    p.gender = 'M'
    AND p.anchor_age BETWEEN 77 AND 87
    AND adm.admission_location = 'EMERGENCY ROOM'
    AND adm.insurance = 'Medicare'
    AND diag.seq_num = 1  -- principal diagnosis
    AND (
        (d.icd_version = 10 AND d.icd_code LIKE 'J18%')  -- ICD-10 pneumonia
        OR
        (d.icd_version = 9 AND d.icd_code LIKE '48%')    -- ICD-9 pneumonia (480-486)
    );