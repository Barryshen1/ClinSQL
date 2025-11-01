WITH cohort AS (
    SELECT 
        adm.subject_id, 
        adm.hadm_id, 
        adm.hospital_expire_flag,
        DATETIME_DIFF(adm.dischtime, adm.admittime, DAY) AS los_days,
        pt.anchor_age
    FROM `physionet-data.mimiciv_3_1_hosp.admissions` adm
    INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` pt
        ON adm.subject_id = pt.subject_id
    WHERE pt.gender = 'M'
        AND pt.anchor_age BETWEEN 44 AND 54
),

charlson AS (
    -- Simplified Charlson computation using ICD-10 and ICD-9 mappings (from mimic-iv concept)
    -- This is a placeholder; in practice, use the full Charlson query from MIMIC-IV concepts
    SELECT 
        hadm_id,
        CASE 
            WHEN score <= 1 THEN '0-1'
            WHEN score = 2 THEN '2'
            ELSE '>=3'
        END AS charlson_category
    FROM (
        SELECT 
            hadm_id,
            SUM(weight) AS score
        FROM (
            SELECT 
                diag.hadm_id,
                CASE
                    WHEN diag.icd_version = 9 THEN comorb.icd9_code
                    WHEN diag.icd_version = 10 THEN comorb.icd10_code
                END AS code,
                comorb.weight
            FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` diag
            INNER JOIN (
                -- This is a simplified table of Charlson comorbidities; in practice, use the full table.
                SELECT ' myocardial_infarct' AS comorbidity, 1 AS weight, '410' AS icd9_code, 'I21' AS icd10_code UNION ALL
                SELECT 'congestive_heart_failure' AS comorbidity, 1 AS weight, '428' AS icd9_code, 'I50' AS icd10_code
                -- ... include all comorbidities from Charlson
            ) comorb
            ON (diag.icd_version = 9 AND diag.icd_code LIKE CONCAT(comorb.icd9_code, '%')) 
                OR (diag.icd_version = 10 AND diag.icd_code LIKE CONCAT(comorb.icd10_code, '%'))
        )
        GROUP BY hadm_id
    )
),

icu_flag AS (
    SELECT 
        hadm_id,
        CASE WHEN COUNT(stay_id) > 0 THEN 'ICU' ELSE 'No ICU' END AS icu_status
    FROM `physionet-data.mimiciv_3_1_icu.icustays`
    GROUP BY hadm_id
),

mech_vent AS (
    SELECT 
        hadm_id,
        MAX(1) AS mech_vent_flag
    FROM (
        -- ICD procedures
        SELECT hadm_id
        FROM `physionet-data.mimiciv_3_1_hosp.procedures_icd`
        WHERE 
            (icd_version = 9 AND icd_code LIKE '96.7%') OR
            (icd_version = 10 AND (
                icd_code LIKE '5A1955Z%' OR 
                icd_code LIKE '5A0935Z%' OR 
                icd_code LIKE '5A0945Z%' OR 
                icd_code LIKE '5A0955Z%'
            ))
        UNION DISTINCT
        -- Procedure events
        SELECT hadm_id
        FROM `physionet-data.mimiciv_3_1_icu.procedureevents`
        WHERE itemid IN (
            227194 -- "Tracheostomy"
            -- Add other relevant itemids for mechanical ventilation
        )
    ) 
    GROUP BY hadm_id
),

vasopressor AS (
    SELECT 
        hadm_id,
        MAX(1) AS vasopressor_flag
    FROM `physionet-data.mimiciv_3_1_icu.inputevents`
    WHERE itemid IN (
        221906 -- norepinephrine
        , 221289 -- epinephrine
        , 222315 -- vasopressin
        , 221662 -- dopamine
        , 221749 -- phenylephrine
    )
    GROUP BY hadm_id
),

rrt AS (
    SELECT 
        hadm_id,
        MAX(1) AS rrt_flag
    FROM `physionet-data.mimiciv_3_1_hosp.procedures_icd`
    WHERE 
        (icd_version = 9 AND icd_code IN ('39.95', '54.98')) OR
        (icd_version = 10 AND icd_code LIKE '5A1D%')
    GROUP BY hadm_id
),

combined AS (
    SELECT 
        c.subject_id,
        c.hadm_id,
        c.hospital_expire_flag AS mortality,
        CASE WHEN c.los_days <= 7 THEN '<=7' ELSE '>7' END AS los_category,
        COALESCE(ch.charlson_category, '0-1') AS charlson_category, -- default to lowest if missing
        COALESCE(icu.icu_status, 'No ICU') AS icu_status,
        COALESCE(mv.mech_vent_flag, 0) AS mech_vent,
        COALESCE(vs.vasopressor_flag, 0) AS vasopressor,
        COALESCE(rr.rrt_flag, 0) AS rrt
    FROM cohort c
    LEFT JOIN charlson ch ON c.hadm_id = ch.hadm_id
    LEFT JOIN icu_flag icu ON c.hadm_id = icu.hadm_id
    LEFT JOIN mech_vent mv ON c.hadm_id = mv.hadm_id
    LEFT JOIN vasopressor vs ON c.hadm_id = vs.hadm_id
    LEFT JOIN rrt rr ON c.hadm_id = rr.hadm_id
)

SELECT 
    icu_status,
    los_category,
    charlson_category,
    COUNT(*) AS n,
    -- Mortality with CI
    ROUND(100 * AVG(mortality), 1) AS mortality_percent,
    ROUND(100 * (AVG(mortality) - 1.96 * SQRT(AVG(mortality) * (1 - AVG(mortality)) / COUNT(*))), 1) AS mortality_ci_lower,
    ROUND(100 * (AVG(mortality) + 1.96 * SQRT(AVG(mortality) * (1 - AVG(mortality)) / COUNT(*))), 1) AS mortality_ci_upper,
    -- Other prevalences
    ROUND(100 * AVG(mech_vent), 1) AS mech_vent_percent,
    ROUND(100 * AVG(vasopressor), 1) AS vasopressor_percent,
    ROUND(100 * AVG(rrt), 1) AS rrt_percent
FROM combined
GROUP BY icu_status, los_category, charlson_category
ORDER BY icu_status, los_category, charlson_category;