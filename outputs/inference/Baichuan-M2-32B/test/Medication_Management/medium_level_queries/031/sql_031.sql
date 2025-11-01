WITH eligible_admissions AS (
    SELECT 
        a.hadm_id,
        a.subject_id,
        a.admittime,
        a.dischtime
    FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
    INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` p 
        ON a.subject_id = p.subject_id
    WHERE p.gender = 'M'
      AND p.anchor_age BETWEEN 53 AND 63
),
diagnoses AS (
    SELECT 
        d1.hadm_id,
        COUNT(DISTINCT CASE 
            WHEN d1.icd_code LIKE 'E1%' THEN 'diabetes'
            WHEN d1.icd_code LIKE 'I50%' THEN 'heart_failure'
        END) AS diagnosis_count
    FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d1
    WHERE d1.icd_code LIKE 'E1%' OR d1.icd_code LIKE 'I50%'
    GROUP BY d1.hadm_id
    HAVING diagnosis_count = 2
),
cohort AS (
    SELECT 
        e.hadm_id,
        e.subject_id,
        e.admittime,
        e.dischtime
    FROM eligible_admissions e
    INNER JOIN diagnoses d ON e.hadm_id = d.hadm_id
),
glp1_prescriptions AS (
    SELECT 
        p.hadm_id,
        p.starttime,
        ROW_NUMBER() OVER (PARTITION BY p.hadm_id ORDER BY p.starttime) AS rn
    FROM `physionet-data.mimiciv_3_1_hosp.prescriptions` p
    WHERE 
        (LOWER(p.drug) LIKE '%semaglutide%' 
         OR LOWER(p.drug) LIKE '%liraglutide%' 
         OR LOWER(p.drug) LIKE '%exenatide%' 
         OR LOWER(p.drug) LIKE '%dulaglutide%' 
         OR LOWER(p.drug) LIKE '%tirzepatide%' 
         OR LOWER(p.drug) LIKE '%albiglutide%') 
        AND LOWER(p.route) IN ('inj', 'sc', 'im', 'subcutaneous', 'intramuscular')
),
first_glp1 AS (
    SELECT 
        g.hadm_id,
        g.starttime
    FROM glp1_prescriptions g
    WHERE g.rn = 1
),
time_windows AS (
    SELECT 
        c.hadm_id,
        c.admittime,
        c.dischtime,
        CASE 
            WHEN g.starttime BETWEEN c.admittime AND c.admittime + INTERVAL 24 HOUR THEN 'first_24h'
            WHEN g.starttime BETWEEN c.dischtime - INTERVAL 12 HOUR AND c.dischtime THEN 'final_12h'
            ELSE NULL 
        END AS time_window
    FROM cohort c
    LEFT JOIN first_glp1 g ON c.hadm_id = g.hadm_id
)
SELECT 
    COUNT(CASE WHEN time_window = 'first_24h' THEN 1 END) * 100.0 / NULLIF(COUNT(*), 0) AS pct_first_24h,
    COUNT(CASE WHEN time_window = 'final_12h' THEN 1 END) * 100.0 / NULLIF(COUNT(*), 0) AS pct_final_12h
FROM time_windows;