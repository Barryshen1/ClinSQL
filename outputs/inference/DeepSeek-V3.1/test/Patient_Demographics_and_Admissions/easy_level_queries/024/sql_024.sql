WITH first_admissions AS (
    SELECT 
        a.subject_id,
        a.hadm_id,
        a.admittime,
        a.dischtime,
        a.hospital_expire_flag
    FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
    INNER JOIN (
        SELECT 
            subject_id, 
            MIN(admittime) AS first_admittime
        FROM `physionet-data.mimiciv_3_1_hosp.admissions`
        GROUP BY subject_id
    ) first 
        ON a.subject_id = first.subject_id 
        AND a.admittime = first.first_admittime
),
cabg_codes AS (
    SELECT 
        icd_code, 
        icd_version
    FROM `physionet-data.mimiciv_3_1_hosp.d_icd_procedures`
    WHERE REGEXP_CONTAINS(LOWER(long_title), r'coronary artery bypass')
),
cabg_patients AS (
    SELECT DISTINCT
        fa.subject_id,
        fa.hadm_id,
        fa.hospital_expire_flag
    FROM first_admissions fa
    INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` p 
        ON fa.subject_id = p.subject_id
    INNER JOIN `physionet-data.mimiciv_3_1_hosp.procedures_icd` proc 
        ON fa.hadm_id = proc.hadm_id
    INNER JOIN cabg_codes cc 
        ON proc.icd_code = cc.icd_code 
        AND proc.icd_version = cc.icd_version
    WHERE 
        p.gender = 'F'
        AND p.anchor_age BETWEEN 35 AND 45
)
SELECT 
    COUNT(*) AS total_patients,
    SUM(hospital_expire_flag) AS deaths,
    ROUND(SUM(hospital_expire_flag) * 100.0 / COUNT(*), 2) AS mortality_percent
FROM cabg_patients;