SELECT COUNT(DISTINCT a.hadm_id)
FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON a.subject_id = p.subject_id
INNER JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
    ON a.hadm_id = d.hadm_id
WHERE 
    p.gender = 'M'
    AND p.anchor_age BETWEEN 43 AND 53
    AND a.admission_location LIKE '%Emergency%'
    AND d.seq_num = 1  -- Principal diagnosis
    AND (d.icd_code LIKE '250.1'  -- ICD-9 DKA
         OR d.icd_code IN ('E10.10', 'E11.10', 'E13.10'))  -- ICD-10 DKA
    AND a.insurance LIKE '%Medicare%';