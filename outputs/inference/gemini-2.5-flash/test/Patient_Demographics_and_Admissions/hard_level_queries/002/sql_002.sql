SELECT
    COUNT(DISTINCT ad.hadm_id) AS total_index_admissions_pneumonia
FROM
    `physionet-data.mimiciv_3_1_hosp.admissions` AS ad
INNER JOIN
    `physionet-data.mimiciv_3_1_hosp.patients` AS pa
    ON ad.subject_id = pa.subject_id
INNER JOIN
    `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` AS diag
    ON ad.subject_id = diag.subject_id AND ad.hadm_id = diag.hadm_id
WHERE
    pa.gender = 'M'
    AND pa.anchor_age BETWEEN 77 AND 87
    AND ad.insurance = 'Medicare'
    AND ad.admission_location = 'EMERGENCY ROOM'
    AND diag.seq_num = 1 -- Principal diagnosis
    AND (
        (diag.icd_version = 9 AND diag.icd_code LIKE '48%') -- ICD-9 codes for pneumonia typically fall within 480-486
        OR
        (diag.icd_version = 10 AND SUBSTR(diag.icd_code, 1, 3) BETWEEN 'J12' AND 'J18') -- ICD-10 codes for pneumonia typically fall within J12-J18
    )
;