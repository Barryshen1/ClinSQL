WITH eligible_patients AS (
    SELECT subject_id
    FROM `physionet-data.mimiciv_3_1_hosp.patients`
    WHERE gender = 'M'
      AND anchor_age BETWEEN 79 AND 89
),
eligible_admissions AS (
    SELECT a.*
    FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
    INNER JOIN eligible_patients p ON a.subject_id = p.subject_id
    WHERE a.dischtime IS NOT NULL
),
admissions_with_diagnoses AS (
    SELECT 
        a.*,
        EXISTS (
            SELECT 1
            FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
            WHERE d.hadm_id = a.hadm_id
              AND d.icd_version = 10
              AND d.icd_code LIKE 'E11%'
        ) AS has_diabetes,
        EXISTS (
            SELECT 1
            FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
            WHERE d.hadm_id = a.hadm_id
              AND d.icd_version = 10
              AND d.icd_code LIKE 'I50%'
        ) AS has_heart_failure
    FROM eligible_admissions a
),
final_admissions AS (
    SELECT *
    FROM admissions_with_diagnoses
    WHERE has_diabetes AND has_heart_failure
),
glp1_drugs AS (
    SELECT 'semaglutide' AS drug
    UNION ALL SELECT 'liraglutide'
    UNION ALL SELECT 'dulaglutide'
    UNION ALL SELECT 'exenatide'
    UNION ALL SELECT 'albiglutide'
    UNION ALL SELECT 'lixisenatide'
    UNION ALL SELECT 'tirzepatide'
    UNION ALL SELECT 'luseogliflozin'
    UNION ALL SELECT 'enfortumab'
),
result_per_admission AS (
    SELECT 
        a.*,
        CASE WHEN EXISTS (
            SELECT 1
            FROM `physionet-data.mimiciv_3_1_hosp.prescriptions` p
            WHERE p.hadm_id = a.hadm_id
              AND p.subject_id = a.subject_id
              AND p.starttime >= a.admittime
              AND p.starttime < a.admittime + INTERVAL 12 HOUR
              AND LOWER(p.drug) IN (SELECT drug FROM glp1_drugs)
              AND p.starttime IS NOT NULL
        ) THEN 1 ELSE 0 END AS window1_initiated,
        CASE WHEN EXISTS (
            SELECT 1
            FROM `physionet-data.mimiciv_3_1_hosp.prescriptions` p
            WHERE p.hadm_id = a.hadm_id
              AND p.subject_id = a.subject_id
              AND p.starttime >= a.dischtime - INTERVAL 24 HOUR
              AND p.starttime <= a.dischtime
              AND LOWER(p.drug) IN (SELECT drug FROM glp1_drugs)
              AND p.starttime IS NOT NULL
        ) THEN 1 ELSE 0 END AS window2_initiated
    FROM final_admissions a
)
SELECT 
    COUNT(*) AS total_admissions,
    SUM(window1_initiated) AS window1_count,
    SUM(window2_initiated) AS window2_count,
    (SUM(window1_initiated) * 100.0 / NULLIF(COUNT(*), 0)) AS window1_percent,
    (SUM(window2_initiated) * 100.0 / NULLIF(COUNT(*), 0)) AS window2_percent,
    ((SUM(window2_initiated) - SUM(window1_initiated)) * 100.0 / NULLIF(COUNT(*), 0)) AS net_change
FROM result_per_admission;