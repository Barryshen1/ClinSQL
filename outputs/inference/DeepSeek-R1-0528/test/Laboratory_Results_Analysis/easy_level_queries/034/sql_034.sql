WITH hf_admissions AS (
    SELECT DISTINCT 
        p.subject_id, 
        a.hadm_id
    FROM `physionet-data.mimiciv_3_1_hosp.patients` p
    INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a
        ON p.subject_id = a.subject_id
    INNER JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` diag
        ON a.hadm_id = diag.hadm_id
    WHERE 
        p.gender = 'M'
        AND ( 
            (diag.icd_version = 9 AND diag.icd_code LIKE '428%') 
            OR 
            (diag.icd_version = 10 AND diag.icd_code LIKE 'I50%')
        )
        AND ( 
            p.anchor_age + (EXTRACT(YEAR FROM a.admittime) - p.anchor_year) = 65
        )
)
SELECT MIN(le.valuenum) AS min_sodium
FROM `physionet-data.mimiciv_3_1_hosp.labevents` le
INNER JOIN hf_admissions ha
    ON le.hadm_id = ha.hadm_id
WHERE le.itemid = 50824;