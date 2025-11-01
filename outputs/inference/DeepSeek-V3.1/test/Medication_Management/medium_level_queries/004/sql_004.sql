WITH cohort AS (
    SELECT 
        adm.subject_id, 
        adm.hadm_id, 
        adm.admittime, 
        adm.dischtime
    FROM `physionet-data.mimiciv_3_1_hosp.patients` pat
    INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` adm
        ON pat.subject_id = adm.subject_id
    WHERE pat.gender = 'M'
        AND pat.anchor_age BETWEEN 45 AND 55
        AND EXISTS (
            SELECT 1
            FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` diag
            WHERE diag.subject_id = adm.subject_id
                AND diag.hadm_id = adm.hadm_id
                AND (
                    (diag.icd_version = 10 AND diag.icd_code LIKE 'E11%') 
                    OR (diag.icd_version = 9 AND diag.icd_code LIKE '250%' AND (diag.icd_code LIKE '%0' OR diag.icd_code LIKE '%2'))
                )
        )
        AND EXISTS (
            SELECT 1
            FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` diag
            WHERE diag.subject_id = adm.subject_id
                AND diag.hadm_id = adm.hadm_id
                AND (
                    (diag.icd_version = 10 AND diag.icd_code LIKE 'I50%')
                    OR (diag.icd_version = 9 AND diag.icd_code LIKE '428%')
                )
        )
),

glp1_prescriptions AS (
    SELECT 
        subject_id,
        hadm_id,
        starttime,
        stoptime,
        drug
    FROM `physionet-data.mimiciv_3_1_hosp.prescriptions`
    WHERE REGEXP_CONTAINS(LOWER(drug), r'exenatide|liraglutide|semaglutide|dulaglutide|lixisenatide|albiglutide|tirzepatide')
),

started_within_72h AS (
    SELECT 
        c.hadm_id,
        MAX(1) AS glp1_started_72h
    FROM cohort c
    INNER JOIN glp1_prescriptions g
        ON c.subject_id = g.subject_id
        AND c.hadm_id = g.hadm_id
    WHERE g.starttime BETWEEN c.admittime AND DATETIME_ADD(c.admittime, INTERVAL 72 HOUR)
    GROUP BY c.hadm_id
),

active_in_last_48h AS (
    SELECT 
        c.hadm_id,
        MAX(1) AS glp1_last_48h
    FROM cohort c
    INNER JOIN glp1_prescriptions g
        ON c.subject_id = g.subject_id
        AND c.hadm_id = g.hadm_id
    WHERE g.starttime <= c.dischtime
        AND (g.stoptime IS NULL OR g.stoptime >= DATETIME_SUB(c.dischtime, INTERVAL 48 HOUR))
    GROUP BY c.hadm_id
)

SELECT 
    COUNT(*) AS total_admissions,
    COUNT(s.glp1_started_72h) AS count_started_72h,
    COUNT(a.glp1_last_48h) AS count_last_48h,
    ROUND(COUNT(s.glp1_started_72h) * 100.0 / COUNT(*), 2) AS percent_started_72h,
    ROUND(COUNT(a.glp1_last_48h) * 100.0 / COUNT(*), 2) AS percent_last_48h,
    ROUND(COUNT(a.glp1_last_48h) * 100.0 / COUNT(*), 2) - ROUND(COUNT(s.glp1_started_72h) * 100.0 / COUNT(*), 2) AS net_change
FROM cohort c
LEFT JOIN started_within_72h s
    ON c.hadm_id = s.hadm_id
LEFT JOIN active_in_last_48h a
    ON c.hadm_id = a.hadm_id;