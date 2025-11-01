WITH cohort AS (
    SELECT 
        adm.subject_id, 
        adm.hadm_id, 
        -- Calculate time windows for each admission
        adm.admittime,
        adm.dischtime,
        DATETIME_ADD(adm.admittime, INTERVAL 72 HOUR) AS first_72h_end,
        DATETIME_SUB(adm.dischtime, INTERVAL 72 HOUR) AS final_72h_start

    FROM `physionet-data.mimiciv_3_1_hosp.admissions` adm
    INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` pat
        ON adm.subject_id = pat.subject_id
    WHERE 
        pat.gender = 'F'
        AND pat.anchor_age BETWEEN 50 AND 60
        AND EXISTS (
            SELECT 1
            FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` diag
            WHERE 
                diag.subject_id = adm.subject_id 
                AND diag.hadm_id = adm.hadm_id
                AND (
                    -- ICD-10 diabetes
                    (diag.icd_version = 10 AND diag.icd_code LIKE 'E1[0-1]%')
                    OR
                    -- ICD-9 diabetes
                    (diag.icd_version = 9 AND diag.icd_code LIKE '250%')
                )
        )
        AND EXISTS (
            SELECT 1
            FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` diag
            WHERE 
                diag.subject_id = adm.subject_id 
                AND diag.hadm_id = adm.hadm_id
                AND (
                    -- ICD-10 heart failure
                    (diag.icd_version = 10 AND diag.icd_code LIKE 'I50%')
                    OR
                    -- ICD-9 heart failure
                    (diag.icd_version = 9 AND diag.icd_code LIKE '428%')
                )
        )
),

glp1_prescriptions AS (
    SELECT 
        p.subject_id,
        p.hadm_id,
        p.starttime,
        -- Check if in first 72h
        CASE WHEN p.starttime BETWEEN c.admittime AND c.first_72h_end THEN 1 ELSE 0 END AS in_first_72h,
        -- Check if in final 72h (and also within admission)
        CASE WHEN p.starttime BETWEEN c.final_72h_start AND c.dischtime THEN 1 ELSE 0 END AS in_final_72h
    FROM `physionet-data.mimiciv_3_1_hosp.prescriptions` p
    INNER JOIN cohort c
        ON p.hadm_id = c.hadm_id
    WHERE 
        LOWER(p.drug) LIKE '%exenatide%'
        OR LOWER(p.drug) LIKE '%liraglutide%'
        OR LOWER(p.drug) LIKE '%semaglutide%'
        OR LOWER(p.drug) LIKE '%dulaglutide%'
        -- Ensure the prescription is during the admission
        AND p.starttime BETWEEN c.admittime AND c.dischtime
),

admission_flags AS (
    SELECT 
        c.hadm_id,
        -- Check if any GLP-1 started in first 72h
        MAX(CASE WHEN gp.in_first_72h = 1 THEN 1 ELSE 0 END) AS glp1_first_72h,
        -- Check if any GLP-1 started in final 72h
        MAX(CASE WHEN gp.in_final_72h = 1 THEN 1 ELSE 0 END) AS glp1_final_72h
    FROM cohort c
    LEFT JOIN glp1_prescriptions gp
        ON c.hadm_id = gp.hadm_id
    GROUP BY c.hadm_id
)

SELECT 
    COUNT(hadm_id) AS total_admissions,
    SUM(glp1_first_72h) AS initiations_first_72h,
    SUM(glp1_final_72h) AS initiations_final_72h,
    ROUND(SAFE_DIVIDE(SUM(glp1_first_72h), COUNT(hadm_id)) * 100, 2) AS rate_first_72h_percent,
    ROUND(SAFE_DIVIDE(SUM(glp1_final_72h), COUNT(hadm_id)) * 100, 2) AS rate_final_72h_percent,
    ROUND(SAFE_DIVIDE(SUM(glp1_final_72h) - SUM(glp1_first_72h), COUNT(hadm_id)) * 100, 2) AS absolute_change_percent,
    ROUND(SAFE_DIVIDE(SUM(glp1_final_72h) - SUM(glp1_first_72h), NULLIF(SUM(glp1_first_72h), 0)) * 100, 2) AS relative_change_percent
FROM admission_flags;