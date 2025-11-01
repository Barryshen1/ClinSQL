WITH base_admissions AS (
    SELECT 
        adm.subject_id, 
        adm.hadm_id, 
        adm.admittime, 
        adm.dischtime,
        -- Calculate exact age at admission
        (EXTRACT(YEAR FROM adm.admittime) - p.anchor_year + p.anchor_age) AS age_at_admission,
        -- Define time windows (adjust for short stays)
        LEAST(DATETIME_ADD(adm.admittime, INTERVAL 12 HOUR), adm.dischtime) AS first_12h_end,
        GREATEST(adm.admittime, DATETIME_SUB(adm.dischtime, INTERVAL 12 HOUR)) AS final_12h_start
    FROM `physionet-data.mimiciv_3_1_hosp.admissions` adm
    INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
        ON adm.subject_id = p.subject_id
    WHERE 
        p.gender = 'M'
        AND (EXTRACT(YEAR FROM adm.admittime) - p.anchor_year + p.anchor_age) BETWEEN 48 AND 58
),
admissions_with_conditions AS (
    SELECT base.*
    FROM base_admissions base
    WHERE 
        -- Type 2 Diabetes
        EXISTS (
            SELECT 1 
            FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` diag 
            WHERE 
                diag.subject_id = base.subject_id 
                AND diag.hadm_id = base.hadm_id
                AND (
                    (diag.icd_version = 9 AND (diag.icd_code LIKE '250.%0' OR diag.icd_code LIKE '250.%2'))
                    OR (diag.icd_version = 10 AND diag.icd_code LIKE 'E11%')
                )
        )
        -- Heart Failure
        AND EXISTS (
            SELECT 1 
            FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` diag 
            WHERE 
                diag.subject_id = base.subject_id 
                AND diag.hadm_id = base.hadm_id
                AND (
                    (diag.icd_version = 9 AND diag.icd_code LIKE '428%')
                    OR (diag.icd_version = 10 AND diag.icd_code LIKE 'I50%')
                )
        )
),
admissions_with_glp1_flags AS (
    SELECT 
        a.*,
        -- Flag if GLP-1 given in first 12h
        CASE WHEN EXISTS (
            SELECT 1 
            FROM `physionet-data.mimiciv_3_1_hosp.emar` e
            WHERE 
                e.subject_id = a.subject_id 
                AND e.hadm_id = a.hadm_id
                AND e.charttime BETWEEN a.admittime AND a.first_12h_end
                AND REGEXP_CONTAINS(LOWER(e.medication), r'exenatide|liraglutide|dulaglutide|semaglutide|lixisenatide|albiglutide|tirzepatide')
        ) THEN 1 ELSE 0 END AS glp1_first_12h,
        -- Flag if GLP-1 given in final 12h
        CASE WHEN EXISTS (
            SELECT 1 
            FROM `physionet-data.mimiciv_3_1_hosp.emar` e
            WHERE 
                e.subject_id = a.subject_id 
                AND e.hadm_id = a.hadm_id
                AND e.charttime BETWEEN a.final_12h_start AND a.dischtime
                AND REGEXP_CONTAINS(LOWER(e.medication), r'exenatide|liraglutide|dulaglutide|semaglutide|lixisenatide|albiglutide|tirzepatide')
        ) THEN 1 ELSE 0 END AS glp1_final_12h
    FROM admissions_with_conditions a
),
aggregated AS (
    SELECT 
        COUNT(*) AS total_admissions,
        SUM(glp1_first_12h) AS count_first_12h,
        SUM(glp1_final_12h) AS count_final_12h
    FROM admissions_with_glp1_flags
)
SELECT 
    total_admissions,
    count_first_12h,
    count_final_12h,
    ROUND(100.0 * count_first_12h / NULLIF(total_admissions, 0), 2) AS percent_first_12h,
    ROUND(100.0 * count_final_12h / NULLIF(total_admissions, 0), 2) AS percent_final_12h,
    ROUND(
        100.0 * count_final_12h / NULLIF(total_admissions, 0) - 
        100.0 * count_first_12h / NULLIF(total_admissions, 0), 
        2
    ) AS net_change
FROM aggregated;