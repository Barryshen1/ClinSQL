WITH cohort AS (
    -- Female patients aged 38-48 with T2D and heart failure
    SELECT DISTINCT p.subject_id, a.hadm_id, a.admittime, a.dischtime
    FROM `physionet-data.mimiciv_3_1_hosp.patients` p
    INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a
        ON p.subject_id = a.subject_id
    WHERE p.gender = 'F'
        AND p.anchor_age BETWEEN 38 AND 48
        AND a.hadm_id IN (
            -- T2D diagnosis
            SELECT hadm_id
            FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd`
            WHERE icd_code LIKE 'E11%'
            INTERSECT DISTINCT
            -- Heart failure diagnosis
            SELECT hadm_id
            FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd`
            WHERE icd_code LIKE 'I50%'
        )
),

first_72h AS (
    -- Medications in first 72h
    SELECT 
        c.subject_id,
        c.hadm_id,
        MAX(CASE WHEN LOWER(p.drug) LIKE '%insulin%' THEN 1 ELSE 0 END) AS insulin_first72,
        MAX(CASE WHEN LOWER(p.drug) LIKE '%metformin%' 
                  OR LOWER(p.drug) LIKE '%glipizide%'
                  OR LOWER(p.drug) LIKE '%glyburide%'
                  OR LOWER(p.drug) LIKE '%glimepiride%'
                  OR LOWER(p.drug) LIKE '%pioglitazone%'
                  OR LOWER(p.drug) LIKE '%repaglinide%'
                  OR LOWER(p.drug) LIKE '%nateglinide%'
                  OR LOWER(p.drug) LIKE '%sitagliptin%'
                  OR LOWER(p.drug) LIKE '%saxagliptin%'
                  OR LOWER(p.drug) LIKE '%linagliptin%'
                  OR LOWER(p.drug) LIKE '%alogliptin%'
                  OR LOWER(p.drug) LIKE '%canagliflozin%'
                  OR LOWER(p.drug) LIKE '%dapagliflozin%'
                  OR LOWER(p.drug) LIKE '%empagliflozin%'
                  OR LOWER(p.drug) LIKE '%acarbose%'
                  OR LOWER(p.drug) LIKE '%miglitol%'
             THEN 1 ELSE 0 END) AS oral_agent_first72
    FROM cohort c
    LEFT JOIN `physionet-data.mimiciv_3_1_hosp.prescriptions` p
        ON c.hadm_id = p.hadm_id
    WHERE p.starttime BETWEEN c.admittime AND DATETIME_ADD(c.admittime, INTERVAL 72 HOUR)
    GROUP BY c.subject_id, c.hadm_id
),

final_72h AS (
    -- Medications in final 72h
    SELECT 
        c.subject_id,
        c.hadm_id,
        MAX(CASE WHEN LOWER(p.drug) LIKE '%insulin%' THEN 1 ELSE 0 END) AS insulin_final72,
        MAX(CASE WHEN LOWER(p.drug) LIKE '%metformin%' 
                  OR LOWER(p.drug) LIKE '%glipizide%'
                  OR LOWER(p.drug) LIKE '%glyburide%'
                  OR LOWER(p.drug) LIKE '%glimepiride%'
                  OR LOWER(p.drug) LIKE '%pioglitazone%'
                  OR LOWER(p.drug) LIKE '%repaglinide%'
                  OR LOWER(p.drug) LIKE '%nateglinide%'
                  OR LOWER(p.drug) LIKE '%sitagliptin%'
                  OR LOWER(p.drug) LIKE '%saxagliptin%'
                  OR LOWER(p.drug) LIKE '%linagliptin%'
                  OR LOWER(p.drug) LIKE '%alogliptin%'
                  OR LOWER(p.drug) LIKE '%canagliflozin%'
                  OR LOWER(p.drug) LIKE '%dapagliflozin%'
                  OR LOWER(p.drug) LIKE '%empagliflozin%'
                  OR LOWER(p.drug) LIKE '%acarbose%'
                  OR LOWER(p.drug) LIKE '%miglitol%'
             THEN 1 ELSE 0 END) AS oral_agent_final72
    FROM cohort c
    LEFT JOIN `physionet-data.mimiciv_3_1_hosp.prescriptions` p
        ON c.hadm_id = p.hadm_id
    WHERE p.starttime BETWEEN DATETIME_SUB(c.dischtime, INTERVAL 72 HOUR) AND c.dischtime
    GROUP BY c.subject_id, c.hadm_id
)

SELECT 
    'First 72h' AS time_window,
    COUNT(*) AS total_patients,
    SUM(insulin_first72) AS insulin_count,
    ROUND(100 * SUM(insulin_first72) / COUNT(*), 2) AS insulin_pct,
    SUM(oral_agent_first72) AS oral_agent_count,
    ROUND(100 * SUM(oral_agent_first72) / COUNT(*), 2) AS oral_agent_pct
FROM first_72h

UNION ALL

SELECT 
    'Final 72h' AS time_window,
    COUNT(*) AS total_patients,
    SUM(insulin_final72) AS insulin_count,
    ROUND(100 * SUM(insulin_final72) / COUNT(*), 2) AS insulin_pct,
    SUM(oral_agent_final72) AS oral_agent_count,
    ROUND(100 * SUM(oral_agent_final72) / COUNT(*), 2) AS oral_agent_pct
FROM final_72h;