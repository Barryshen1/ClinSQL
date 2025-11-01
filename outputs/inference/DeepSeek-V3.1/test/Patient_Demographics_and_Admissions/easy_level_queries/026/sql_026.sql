WITH first_admission AS (
    SELECT 
        p.subject_id,
        MIN(a.admittime) AS first_admittime
    FROM `physionet-data.mimiciv_3_1_hosp.patients` p
    INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a
        ON p.subject_id = a.subject_id
    GROUP BY p.subject_id
),
cabg_patients AS (
    SELECT 
        fa.subject_id,
        fa.first_admittime
    FROM first_admission fa
    INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a
        ON fa.subject_id = a.subject_id
            AND fa.first_admittime = a.admittime
    INNER JOIN `physionet-data.mimiciv_3_1_hosp.procedures_icd` pc
        ON a.subject_id = pc.subject_id
            AND a.hadm_id = pc.hadm_id
    INNER JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_procedures` dp
        ON pc.icd_code = dp.icd_code
            AND pc.icd_version = dp.icd_version
    WHERE 
        (dp.icd_code LIKE '021%' AND dp.icd_version = 10)  -- ICD-10 CABG codes
        OR (dp.icd_code BETWEEN '3610' AND '3616' AND dp.icd_version = 9)  -- ICD-9 CABG codes
)
SELECT 
    AVG(CAST(a.hospital_expire_flag AS FLOAT64)) AS mortality_rate
FROM cabg_patients cp
INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a
    ON cp.subject_id = a.subject_id
        AND cp.first_admittime = a.admittime
INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON cp.subject_id = p.subject_id
WHERE 
    p.gender = 'M'
    AND p.anchor_age BETWEEN 48 AND 58;