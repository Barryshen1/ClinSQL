WITH cohort_base AS (
    SELECT 
        p.subject_id,
        a.hadm_id,
        a.admittime,
        a.dischtime,
        a.hospital_expire_flag,
        p.dod,
        p.anchor_age,
        p.anchor_year
    FROM 
        `physionet-data.mimiciv_3_1_hosp.patients` p
    INNER JOIN 
        `physionet-data.mimiciv_3_1_hosp.admissions` a 
        ON p.subject_id = a.subject_id
    WHERE 
        p.gender = 'F'
        AND p.anchor_age + EXTRACT(YEAR FROM a.admittime) - p.anchor_year BETWEEN 75 AND 85
        AND EXISTS (
            SELECT 1
            FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
            WHERE 
                d.subject_id = a.subject_id
                AND d.hadm_id = a.hadm_id
                AND (
                    (d.icd_version = 9 AND d.icd_code IN ('491.21','491.22','491.8','491.9','492.8','493.20','493.21','493.22','496'))
                    OR 
                    (d.icd_version = 10 AND d.icd_code IN ('J44.0','J44.1','J44.9'))
                )
        )
),

scs AS (
    SELECT 
        hadm_id,
        MAX(CASE 
            WHEN (icd_version = 9 AND icd_code IN ('428.0','428.1','428.2','428.3','428.4','428.9'))
                OR (icd_version = 10 AND icd_code IN ('I50.20','I50.21','I50.22','I50.23','I50.30','I50.31','I50.32','I50.33','I50.40','I50.41','I50.42','I50.43','I50.9'))
            THEN 1 ELSE 0 
        END) AS chf,
        MAX(CASE 
            WHEN (icd_version = 9 AND icd_code LIKE '250.%')
                OR (icd_version = 10 AND (icd_code LIKE 'E10%' OR icd_code LIKE 'E11%' OR icd_code LIKE 'E12%' OR icd_code LIKE 'E13%' OR icd_code LIKE 'E14%'))
            THEN 1 ELSE 0 
        END) AS diabetes,
        MAX(CASE 
            WHEN (icd_version = 9 AND icd_code IN ('585.1','585.2','585.3','585.4','585.5','585.9'))
                OR (icd_version = 10 AND icd_code IN ('N18.1','N18.2','N18.3','N18.4','N18.5','N18.6','N18.9'))
            THEN 1 ELSE 0 
        END) AS ckd,
        MAX(CASE 
            WHEN (icd_version = 9 AND icd_code IN ('571.0','571.1','571.2','571.3','571.4','571.5','571.6','571.8','571.9','572.2','572.3','572.4','572.8','573.0','573.1','573.2','573.3','573.4','573.8','573.9','V42.7'))
                OR (icd_version = 10 AND icd_code IN ('K70.0','K70.1','K70.2','K70.3','K70.4','K70.9','K71.0','K71.1','K71.2','K71.3','K71.4','K71.5','K71.6','K71.7','K71.8','K71.9','K72.0','K72.1','K72.9','K73.0','K73.1','K73.2','K73.3','K73.4','K73.8','K73.9','K74.0','K74.1','K74.2','K74.3','K74.4','K74.5','K74.6','K74.60','K74.69','K75.0','K75.1','K75.2','K75.3','K75.4','K75.8','K75.9','K76.0','K76.1','K76.2','K76.3','K76.4','K76.5','K76.6','K76.7','K76.8','K76.9','Z94.4'))
            THEN 1 ELSE 0 
        END) AS liver,
        MAX(CASE 
            WHEN (icd_version = 9 AND icd_code IN ('196.0','196.1','196.2','196.3','196.5','196.6','196.8','196.9','199.0','199.1'))
                OR (icd_version = 10 AND icd_code IN ('C77.0','C77.1','C77.2','C77.3','C77.4','C77.5','C77.8','C77.9','C78.00','C78.01','C78.02','C78.1','C78.2','C78.30','C78.39','C78.4','C78.5','C78.6','C78.7','C78.80','C78.89','C79.00','C79.01','C79.02','C79.10','C79.11','C79.19','C79.2','C79.31','C79.32','C79.40','C79.49','C79.51','C79.52','C79.60','C79.61','C79.62','C79.70','C79.71','C79.72','C79.81','C79.82','C79.89','C79.9','C80.0','C80.1','C80.2'))
            THEN 1 ELSE 0 
        END) AS cancer
    FROM 
        `physionet-data.mimiciv_3_1_hosp.diagnoses_icd`
    WHERE 
        hadm_id IN (SELECT hadm_id FROM cohort_base)
    GROUP BY 
        hadm_id
),

complications AS (
    SELECT 
        hadm_id,
        MAX(1) AS major_complication_flag
    FROM (
        -- Mechanical ventilation (procedures)
        SELECT hadm_id
        FROM `physionet-data.mimiciv_3_1_hosp.procedures_icd`
        WHERE 
            (icd_version = 9 AND icd_code IN ('96.70','96.71','96.72'))
            OR 
            (icd_version = 10 AND icd_code IN ('5A09357','5A09457','5A09557','0BH17EZ','0BH18EZ'))
        
        UNION DISTINCT
        
        -- Other complications (diagnoses)
        SELECT hadm_id
        FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd`
        WHERE 
            (icd_version = 9 AND (
                icd_code = '427.5' OR 
                icd_code IN ('785.52','995.92') OR 
                icd_code IN ('584.5','584.6','584.7','584.8','584.9') OR 
                icd_code IN ('512.0','512.1','512.8')
            )) 
            OR 
            (icd_version = 10 AND (
                icd_code IN ('I46.2','I46.8','I46.9') OR 
                icd_code IN ('R65.20','R65.21','R65.3') OR 
                icd_code IN ('N17.0','N17.1','N17.2','N17.8','N17.9') OR 
                icd_code IN ('J93.0','J93.1','J93.8','J93.9')
            ))
    ) 
    GROUP BY 
        hadm_id
),

cohort AS (
    SELECT 
        cb.subject_id,
        cb.hadm_id,
        cb.admittime,
        cb.dischtime,
        cb.hospital_expire_flag,
        cb.dod,
        DATE_DIFF(cb.dischtime, cb.admittime, DAY) AS los,
        CASE 
            WHEN cb.dod IS NOT NULL AND DATE_DIFF(cb.dod, cb.admittime, DAY) <= 90 THEN 1 
            ELSE 0 
        END AS mortality_90d,
        COALESCE(cmp.major_complication_flag, 0) AS major_complication_flag,
        COALESCE(s.chf, 0) + COALESCE(s.diabetes, 0) + COALESCE(s.ckd, 0) + COALESCE(s.liver, 0) + COALESCE(s.cancer, 0) AS scs_score
    FROM 
        cohort_base cb
    LEFT JOIN 
        scs s ON cb.hadm_id = s.hadm_id
    LEFT JOIN 
        complications cmp ON cb.hadm_id = cmp.hadm_id
),

quartiles AS (
    SELECT 
        *,
        NTILE(4) OVER (ORDER BY scs_score) AS scs_quartile
    FROM 
        cohort
),

survivor_los AS (
    SELECT 
        scs_quartile,
        APPROX_QUANTILES(los, 100)[OFFSET(50)] AS median_survivor_los
    FROM 
        quartiles
    WHERE 
        hospital_expire_flag = 0
    GROUP BY 
        scs_quartile
),

broader_mortality AS (
    SELECT 
        AVG(mortality_90d) * 100 AS broader_90d_mortality
    FROM 
        cohort
)

SELECT 
    q.scs_quartile,
    COUNT(*) AS patients_in_quartile,
    AVG(q.mortality_90d) * 100 AS mortality_90d_pct,
    AVG(q.major_complication_flag) * 100 AS major_complication_rate,
    sl.median_survivor_los,
    (SELECT broader_90d_mortality FROM broader_mortality) AS broader_90d_mortality
FROM 
    quartiles q
LEFT JOIN 
    survivor_los sl ON q.scs_quartile = sl.scs_quartile
GROUP BY 
    q.scs_quartile, 
    sl.median_survivor_los
ORDER BY 
    q.scs_quartile;