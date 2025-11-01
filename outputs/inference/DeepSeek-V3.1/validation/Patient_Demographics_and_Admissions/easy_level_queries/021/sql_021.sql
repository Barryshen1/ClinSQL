WITH first_admissions AS (
    SELECT 
        subject_id,
        hadm_id,
        admittime,
        dischtime,
        deathtime,
        hospital_expire_flag
    FROM (
        SELECT 
            subject_id,
            hadm_id,
            admittime,
            dischtime,
            deathtime,
            hospital_expire_flag,
            ROW_NUMBER() OVER (PARTITION BY subject_id ORDER BY admittime) AS rn
        FROM `physionet-data.mimiciv_3_1_hosp.admissions`
    ) 
    WHERE rn = 1
)

SELECT 
    COUNT(*) AS total_patients,
    SUM(fa.hospital_expire_flag) AS deaths,
    ROUND(100.0 * SUM(fa.hospital_expire_flag) / COUNT(*), 2) AS mortality_percent
FROM first_admissions fa
INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` p 
    ON fa.subject_id = p.subject_id
INNER JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` di 
    ON fa.hadm_id = di.hadm_id
WHERE 
    p.gender = 'F'
    AND p.anchor_age BETWEEN 83 AND 93
    AND (
        -- ICD-9 codes for pneumonia
        (di.icd_version = 9 AND di.icd_code IN ('480%', '481', '482%', '483%', '485', '486', '487.0'))
        OR
        -- ICD-10 codes for pneumonia
        (di.icd_version = 10 AND di.icd_code LIKE 'J12%' OR di.icd_code LIKE 'J13%' 
         OR di.icd_code LIKE 'J14%' OR di.icd_code LIKE 'J15%' OR di.icd_code LIKE 'J16%' OR di.icd_code LIKE 'J18%')
    );