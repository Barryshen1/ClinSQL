SELECT
    COUNT(DISTINCT ad.hadm_id) AS total_admissions
FROM
    `physionet-data.mimiciv_3_1_hosp.admissions` AS ad
JOIN
    `physionet-data.mimiciv_3_1_hosp.patients` AS p
    ON ad.subject_id = p.subject_id
JOIN
    `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` AS di
    ON ad.subject_id = di.subject_id AND ad.hadm_id = di.hadm_id
WHERE
    p.gender = 'F' -- Female patients
    AND p.anchor_age BETWEEN 63 AND 73 -- Aged 63–73
    AND ad.insurance = 'Medicare' -- Medicare inpatients
    AND ad.admission_location = 'TRANSFER FROM OTHER HOSPITAL' -- Transferred from another hospital
    AND di.seq_num = 1 -- Principal diagnosis
    AND di.icd_code IN ( -- ICD codes for Atrial Fibrillation (ICD-9 and ICD-10)
        '42731',  -- ICD-9: Atrial fibrillation
        'I480',   -- ICD-10: Paroxysmal atrial fibrillation
        'I481',   -- ICD-10: Persistent atrial fibrillation
        'I482',   -- ICD-10: Chronic atrial fibrillation
        'I4891',  -- ICD-10: Unspecified atrial fibrillation
        'I4892'   -- ICD-10: Unspecified atrial flutter
    )
;