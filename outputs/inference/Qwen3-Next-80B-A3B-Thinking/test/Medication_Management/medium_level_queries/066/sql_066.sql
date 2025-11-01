WITH cohort AS (
    SELECT 
        a.hadm_id, 
        a.admittime, 
        a.dischtime
    FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
    JOIN `physionet-data.mimiciv_3_1_hosp.patients` p 
        ON a.subject_id = p.subject_id
    WHERE 
        p.gender = 'M'
        AND p.anchor_age BETWEEN 58 AND 68
        AND TIMESTAMP_DIFF(a.dischtime, a.admittime, HOUR) >= 72
        AND EXISTS (
            SELECT 1 
            FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d 
            WHERE d.hadm_id = a.hadm_id 
                AND d.icd_code LIKE 'E11%' 
                AND d.icd_version = 10
        )
        AND EXISTS (
            SELECT 1 
            FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d 
            WHERE d.hadm_id = a.hadm_id 
                AND d.icd_code LIKE 'I50%' 
                AND d.icd_version = 10
        )
),
glp1_flags AS (
    SELECT 
        c.hadm_id,
        MAX(CASE 
            WHEN (LOWER(p.drug) LIKE '%liraglutide%' 
                OR LOWER(p.drug) LIKE '%semaglutide%' 
                OR LOWER(p.drug) LIKE '%exenatide%' 
                OR LOWER(p.drug) LIKE '%dulaglutide%' 
                OR LOWER(p.drug) LIKE '%albiglutide%' 
                OR LOWER(p.drug) LIKE '%lixisenatide%')
                AND p.starttime BETWEEN c.admittime AND c.admittime + INTERVAL 72 HOUR
            THEN 1 ELSE 0 
        END) AS started_first_72h,
        MAX(CASE 
            WHEN (LOWER(p.drug) LIKE '%liraglutide%' 
                OR LOWER(p.drug) LIKE '%semaglutide%' 
                OR LOWER(p.drug) LIKE '%exenatide%' 
                OR LOWER(p.drug) LIKE '%dulaglutide%' 
                OR LOWER(p.drug) LIKE '%albiglutide%' 
                OR LOWER(p.drug) LIKE '%lixisenatide%')
                AND p.starttime BETWEEN c.dischtime - INTERVAL 12 HOUR AND c.dischtime
            THEN 1 ELSE 0 
        END) AS started_final_12h
    FROM cohort c
    LEFT JOIN `physionet-data.mimiciv_3_1_hosp.prescriptions` p 
        ON c.hadm_id = p.hadm_id
    GROUP BY c.hadm_id
)
SELECT 
    AVG(started_first_72h) * 100 AS percent_first_72h,
    AVG(started_final_12h) * 100 AS percent_final_12h,
    (AVG(started_final_12h) - AVG(started_first_72h)) * 100 AS absolute_difference
FROM glp1_flags;