WITH filtered_admissions AS (
    SELECT 
        a.subject_id,
        a.hadm_id,
        a.admittime,
        p.anchor_age,
        p.anchor_year
    FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
    INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` p 
        ON a.subject_id = p.subject_id
    WHERE 
        a.admission_location = 'TRANSFER FROM HOSPITAL'
        AND p.gender = 'M'
),
principal_diagnosis AS (
    SELECT 
        subject_id,
        hadm_id
    FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd`
    WHERE 
        seq_num = 1
        AND (
            (icd_code = '585.6' AND icd_version = 9)
            OR 
            (icd_code = 'N18.6' AND icd_version = 10)
        )
),
combined AS (
    SELECT 
        f.subject_id,
        f.hadm_id,
        f.admittime,
        f.anchor_age,
        f.anchor_year
    FROM filtered_admissions f
    INNER JOIN principal_diagnosis p
        ON f.subject_id = p.subject_id AND f.hadm_id = p.hadm_id
)
SELECT 
    COUNT(DISTINCT hadm_id) AS admission_count
FROM combined
WHERE 
    CASE 
        WHEN anchor_age < 90 THEN 
            anchor_age + (EXTRACT(YEAR FROM admittime) - anchor_year)
        ELSE 
            91 + (EXTRACT(YEAR FROM admittime) - anchor_year)
    END BETWEEN 90 AND 100;