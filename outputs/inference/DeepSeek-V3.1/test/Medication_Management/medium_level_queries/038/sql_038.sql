WITH cohort AS (
    SELECT 
        adm.subject_id, 
        adm.hadm_id, 
        adm.admittime, 
        adm.dischtime
    FROM `physionet-data.mimiciv_3_1_hosp.admissions` adm
    INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` pat
        ON adm.subject_id = pat.subject_id
    WHERE 
        pat.gender = 'M'
        AND pat.anchor_age BETWEEN 57 AND 67
        AND adm.hospital_expire_flag = 0  -- exclude in-hospital deaths to avoid bias in final 24h
        AND adm.dischtime IS NOT NULL
        AND DATETIME_DIFF(adm.dischtime, adm.admittime, HOUR) >= 24  -- ensure at least 24h stay
    AND EXISTS (
        SELECT 1
        FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` diag
        WHERE diag.subject_id = adm.subject_id
            AND diag.hadm_id = adm.hadm_id
            AND diag.icd_version = 10
            AND diag.icd_code LIKE 'E1%'  -- Diabetes codes E10-E14
    )
    AND EXISTS (
        SELECT 1
        FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` diag
        WHERE diag.subject_id = adm.subject_id
            AND diag.hadm_id = adm.hadm_id
            AND diag.icd_version = 10
            AND diag.icd_code IN ('I50.2', 'I50.21', 'I50.22', 'I50.23', 'I50.3', 'I50.4', 'I50.9')  -- Acute HF codes
    )
),

glp1_drugs AS (
    SELECT 
        subject_id,
        hadm_id,
        starttime
    FROM `physionet-data.mimiciv_3_1_hosp.prescriptions`
    WHERE 
        LOWER(drug) LIKE '%semaglutide%'
        OR LOWER(drug) LIKE '%liraglutide%'
        OR LOWER(drug) LIKE '%dulaglutide%'
        OR LOWER(drug) LIKE '%exenatide%'
        OR LOWER(drug) LIKE '%lixisenatide%'
        OR LOWER(drug) LIKE '%albiglutide%'
        OR LOWER(drug) LIKE '%tirzepatide%'
        OR LOWER(drug) LIKE '%glp%'
),

cohort_with_glp1 AS (
    SELECT 
        c.subject_id,
        c.hadm_id,
        c.admittime,
        c.dischtime,
        -- Flag if GLP-1 initiated in first 72h
        MAX(CASE WHEN g.starttime BETWEEN c.admittime AND DATETIME_ADD(c.admittime, INTERVAL 72 HOUR) THEN 1 ELSE 0 END) AS glp1_first72h,
        -- Flag if GLP-1 initiated in final 24h
        MAX(CASE WHEN g.starttime BETWEEN DATETIME_SUB(c.dischtime, INTERVAL 24 HOUR) AND c.dischtime THEN 1 ELSE 0 END) AS glp1_final24h
    FROM cohort c
    LEFT JOIN glp1_drugs g
        ON c.subject_id = g.subject_id
        AND c.hadm_id = g.hadm_id
    GROUP BY c.subject_id, c.hadm_id, c.admittime, c.dischtime
)

SELECT
    COUNT(*) AS total_patients,
    SUM(glp1_first72h) AS initiated_first72h,
    SUM(glp1_final24h) AS initiated_final24h,
    ROUND(100.0 * SUM(glp1_first72h) / COUNT(*), 2) AS initiation_rate_first72h_percent,
    ROUND(100.0 * SUM(glp1_final24h) / COUNT(*), 2) AS initiation_rate_final24h_percent,
    ROUND(100.0 * (SUM(glp1_first72h) - SUM(glp1_final24h)) / COUNT(*), 2) AS absolute_change_percent,
    ROUND(100.0 * (SUM(glp1_first72h) - SUM(glp1_final24h)) / NULLIF(SUM(glp1_first72h), 0), 2) AS relative_change_percent
FROM cohort_with_glp1;