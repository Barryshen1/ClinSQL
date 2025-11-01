WITH eligible_admissions AS (
    SELECT 
        a.hadm_id,
        a.subject_id,
        a.admittime,
        a.dischtime
    FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
    INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` p 
        ON a.subject_id = p.subject_id
    WHERE 
        p.gender = 'M'
        AND p.anchor_age BETWEEN 57 AND 67
        AND a.hospital_expire_flag = 0
        AND TIMESTAMP_DIFF(a.dischtime, a.admittime, HOUR) >= 24
        AND EXISTS (
            SELECT 1 
            FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
            INNER JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` dd 
                ON d.icd_code = dd.icd_code AND d.icd_version = dd.icd_version
            WHERE 
                d.hadm_id = a.hadm_id
                AND dd.icd_version = 10
                AND d.icd_code BETWEEN 'E10' AND 'E14'
        )
        AND EXISTS (
            SELECT 1 
            FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
            INNER JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` dd 
                ON d.icd_code = dd.icd_code AND d.icd_version = dd.icd_version
            WHERE 
                d.hadm_id = a.hadm_id
                AND dd.icd_version = 10
                AND d.icd_code IN ('I50.1', 'I50.2', 'I50.9')
        )
),
glp1_prescriptions AS (
    SELECT 
        p.hadm_id,
        p.starttime,
        ROW_NUMBER() OVER (PARTITION BY p.hadm_id ORDER BY p.starttime) AS rn
    FROM `physionet-data.mimiciv_3_1_hosp.prescriptions` p
    WHERE 
        p.drug IS NOT NULL
        AND (
            LOWER(p.drug) LIKE '%glp-1%'
            OR LOWER(p.drug) LIKE '%liraglutide%'
            OR LOWER(p.drug) LIKE '%semaglutide%'
            OR LOWER(p.drug) LIKE '%exenatide%'
            OR LOWER(p.drug) LIKE '%dulaglutide%'
            OR LOWER(p.drug) LIKE '%tirzepatide%'
        )
    AND EXISTS (SELECT 1 FROM eligible_admissions e WHERE e.hadm_id = p.hadm_id)
),
admission_flags AS (
    SELECT 
        e.hadm_id,
        e.admittime,
        e.dischtime,
        -- Check for any GLP-1 prescription in first 72h
        (SELECT COUNT(*) > 0 
         FROM glp1_prescriptions g 
         WHERE g.hadm_id = e.hadm_id 
           AND g.starttime BETWEEN e.admittime AND e.admittime + INTERVAL 72 HOUR) AS has_glp1_first72h,
        -- Check if the first GLP-1 prescription is in first 72h
        (SELECT COUNT(*) > 0 
         FROM glp1_prescriptions g 
         WHERE g.hadm_id = e.hadm_id 
           AND g.rn = 1 
           AND g.starttime BETWEEN e.admittime AND e.admittime + INTERVAL 72 HOUR) AS first_glp1_in_first72h,
        -- Check for any GLP-1 prescription in final 24h
        (SELECT COUNT(*) > 0 
         FROM glp1_prescriptions g 
         WHERE g.hadm_id = e.hadm_id 
           AND g.starttime BETWEEN e.dischtime - INTERVAL 24 HOUR AND e.dischtime) AS has_glp1_final24h,
        -- Check if the first GLP-1 prescription is in final 24h
        (SELECT COUNT(*) > 0 
         FROM glp1_prescriptions g 
         WHERE g.hadm_id = e.hadm_id 
           AND g.rn = 1 
           AND g.starttime BETWEEN e.dischtime - INTERVAL 24 HOUR AND e.dischtime) AS first_glp1_in_final24h
    FROM eligible_admissions e
),
aggregated_data AS (
    SELECT 
        COUNT(*) AS total_admissions,
        SUM(has_glp1_first72h) AS count_has_glp1_first72h,
        SUM(first_glp1_in_first72h) AS count_first_glp1_first72h,
        SUM(has_glp1_final24h) AS count_has_glp1_final24h,
        SUM(first_glp1_in_final24h) AS count_first_glp1_final24h
    FROM admission_flags
)
SELECT 
    (COUNT_has_glp1_first72h * 100.0 / total_admissions) AS prevalence_first_72h,
    (COUNT_first_glp1_first72h * 100.0 / total_admissions) AS initiation_rate_first_72h,
    (COUNT_has_glp1_final24h * 100.0 / total_admissions) AS prevalence_final_24h,
    (COUNT_first_glp1_final24h * 100.0 / total_admissions) AS initiation_rate_final_24h,
    (prevalence_final_24h - prevalence_first_72h) AS absolute_change,
    (prevalence_final_24h - prevalence_first_72h) / NULLIF(prevalence_first_72h, 0) * 100 AS relative_change
FROM aggregated_data;