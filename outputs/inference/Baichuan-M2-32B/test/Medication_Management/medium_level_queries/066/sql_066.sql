WITH eligible_admissions AS (
    SELECT 
        a.hadm_id,
        a.subject_id,
        a.admittime,
        a.dischtime,
        -- Calculate age at admission: anchor_age + (admission_year - anchor_year)
        p.anchor_age + (EXTRACT(YEAR FROM a.admittime) - p.anchor_year) AS age_at_admission
    FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
    INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` p 
        ON a.subject_id = p.subject_id
    WHERE 
        p.gender = 'M'
        AND TIMESTAMP_DIFF(a.dischtime, a.admittime, HOUR) >= 72
        AND p.anchor_age + (EXTRACT(YEAR FROM a.admittime) - p.anchor_year) BETWEEN 58 AND 68
),
diagnoses AS (
    SELECT 
        d1.hadm_id,
        MAX(CASE WHEN d1.icd_code LIKE 'E11%' THEN 1 ELSE 0 END) AS has_t2dm,
        MAX(CASE WHEN d2.icd_code LIKE 'I50%' THEN 1 ELSE 0 END) AS has_hf
    FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d1
    INNER JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d2 
        ON d1.hadm_id = d2.hadm_id
    WHERE 
        d1.icd_version = 10
        AND d2.icd_version = 10
        AND d1.hadm_id IN (SELECT hadm_id FROM eligible_admissions)
    GROUP BY d1.hadm_id
    HAVING has_t2dm = 1 AND has_hf = 1
),
glp1_prescriptions AS (
    SELECT 
        p.hadm_id,
        p.starttime,
        -- Check for GLP-1 agonist drugs using common names
        CASE WHEN LOWER(p.drug) LIKE '%glp-1%' 
             OR LOWER(p.drug) LIKE '%semaglutide%' 
             OR LOWER(p.drug) LIKE '%liraglutide%' 
             OR LOWER(p.drug) LIKE '%dulaglutide%' 
             OR LOWER(p.drug) LIKE '%exenatide%' 
             OR LOWER(p.drug) LIKE '%lixisenatide%' 
             OR LOWER(p.drug) LIKE '%albiglutide%' 
             THEN 1 
             ELSE 0 
        END AS is_glp1
    FROM `physionet-data.mimiciv_3_1_hosp.prescriptions` p
    WHERE p.hadm_id IN (SELECT hadm_id FROM diagnoses)
),
admission_windows AS (
    SELECT 
        e.hadm_id,
        e.admittime,
        e.dischtime,
        TIMESTAMP_ADD(e.admittime, INTERVAL 72 HOUR) AS first72h_end,
        TIMESTAMP_SUB(e.dischtime, INTERVAL 12 HOUR) AS final12h_start
    FROM eligible_admissions e
    INNER JOIN diagnoses d ON e.hadm_id = d.hadm_id
),
glp1_in_windows AS (
    SELECT 
        w.hadm_id,
        MAX(CASE WHEN g.starttime BETWEEN w.admittime AND w.first72h_end THEN 1 ELSE 0 END) AS glp1_first72h,
        MAX(CASE WHEN g.starttime BETWEEN w.final12h_start AND w.dischtime THEN 1 ELSE 0 END) AS glp1_final12h
    FROM admission_windows w
    LEFT JOIN glp1_prescriptions g 
        ON w.hadm_id = g.hadm_id
    GROUP BY w.hadm_id
)
SELECT 
    (SUM(glp1_first72h) * 100.0 / COUNT(*)) AS percent_first72h,
    (SUM(glp1_final12h) * 100.0 / COUNT(*)) AS percent_final12h,
    ABS((SUM(glp1_first72h) * 100.0 / COUNT(*)) - (SUM(glp1_final12h) * 100.0 / COUNT(*))) AS abs_diff
FROM glp1_in_windows;