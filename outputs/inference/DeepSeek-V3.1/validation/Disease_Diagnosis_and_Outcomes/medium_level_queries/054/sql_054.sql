WITH
-- Base cohort: 44-year-old male elective admissions
-- Filter for only discharged patients to know final LOS and mortality status.
cohort AS (
    SELECT
        adm.subject_id,
        adm.hadm_id,
        adm.admittime,
        adm.dischtime,
        adm.hospital_expire_flag,
        -- Calculate LOS in days for discharged patients
        DATETIME_DIFF(adm.dischtime, adm.admittime, DAY) AS los_days,
        -- Group LOS
        CASE
            WHEN DATETIME_DIFF(adm.dischtime, adm.admittime, DAY) <= 3 THEN '<=3'
            WHEN DATETIME_DIFF(adm.dischtime, adm.admittime, DAY) BETWEEN 4 AND 6 THEN '4-6'
            WHEN DATETIME_DIFF(adm.dischtime, adm.admittime, DAY) BETWEEN 7 AND 10 THEN '7-10'
            ELSE '>10'
        END AS los_group,
        -- ICU vs non-ICU: if hadm_id exists in icustays, then ICU, else non-ICU
        CASE WHEN icu.hadm_id IS NOT NULL THEN 'ICU' ELSE 'non-ICU' END AS icu_flag
    FROM `physionet-data.mimiciv_3_1_hosp.admissions` adm
    INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` pat
        ON adm.subject_id = pat.subject_id
    LEFT JOIN (
        SELECT DISTINCT hadm_id
        FROM `physionet-data.mimiciv_3_1_icu.icustays`
    ) icu ON adm.hadm_id = icu.hadm_id
    WHERE pat.gender = 'M'
        AND pat.anchor_age = 44
        AND adm.admission_type = 'ELECTIVE'
        -- Only include patients who have been discharged
        AND adm.dischtime IS NOT NULL
),

-- Compute Charlson Comorbidity Index for each admission using Quan et al. mapping
charlson AS (
    WITH
    -- Map ICD-10 codes to Charlson comorbidities and weights (Quan et al.)
    charlson_map AS (
        SELECT
            icd_code,
            icd_version,
            weight,
            comorbidity
        FROM UNNEST([
            STRUCT('I09.9' AS icd_code, 9 AS icd_version, 1 AS weight, 'CHF' AS comorbidity),
            STRUCT('I11.0' AS icd_code, 9 AS icd_version, 1 AS weight, 'CHF' AS comorbidity),
            STRUCT('I13.0' AS icd_code, 9 AS icd_version, 1 AS weight, 'CHF' AS comorbidity),
            STRUCT('I13.2' AS icd_code, 9 AS icd_version, 1 AS weight, 'CHF' AS comorbidity),
            STRUCT('I25.5' AS icd_code, 9 AS icd_version, 1 AS weight, 'CHF' AS comorbidity),
            STRUCT('I42.0' AS icd_code, 9 AS icd_version, 1 AS weight, 'CHF' AS comorbidity),
            STRUCT('I42.5' AS icd_code, 9 AS icd_version, 1 AS weight, 'CHF' AS comorbidity),
            STRUCT('I42.6' AS icd_code, 9 AS icd_version, 1 AS weight, 'CHF' AS comorbidity),
            STRUCT('I42.7' AS icd_code, 9 AS icd_version, 1 AS weight, 'CHF' AS comorbidity),
            STRUCT('I42.8' AS icd_code, 9 AS icd_version, 1 AS weight, 'CHF' AS comorbidity),
            STRUCT('I42.9' AS icd_code, 9 AS icd_version, 1 AS weight, 'CHF' AS comorbidity),
            STRUCT('I43.' AS icd_code, 9 AS icd_version, 1 AS weight, 'CHF' AS comorbidity),
            STRUCT('I50.' AS icd_code, 9 AS icd_version, 1 AS weight, 'CHF' AS comorbidity),
            STRUCT('I50.0' AS icd_code, 9 AS icd_version, 1 AS weight, 'CHF' AS comorbidity),
            STRUCT('I50.1' AS icd_code, 9 AS icd_version, 1 AS weight, 'CHF' AS comorbidity),
            STRUCT('I50.9' AS icd_code, 9 AS icd_version, 1 AS weight, 'CHF' AS comorbidity),
            STRUCT('P29.0' AS icd_code, 9 AS icd_version, 1 AS weight, 'CHF' AS comorbidity),
            -- ... (This is a truncated list. In practice, include the full Quan mapping for all 17 categories)
            -- Myocardial Infarction (MI)
            STRUCT('I21.' AS icd_code, 9 AS icd_version, 1 AS weight, 'MI' AS comorbidity),
            STRUCT('I22.' AS icd_code, 9 AS icd_version, 1 AS weight, 'MI' AS comorbidity),
            STRUCT('I25.2' AS icd_code, 9 AS icd_version, 1 AS weight, 'MI' AS comorbidity),
            -- Peripheral Vascular Disease (PVD)
            STRUCT('I70.' AS icd_code, 9 AS icd_version, 1 AS weight, 'PVD' AS comorbidity),
            STRUCT('I71.' AS icd_code, 9 AS icd_version, 1 AS weight, 'PVD' AS comorbidity),
            -- Cerebrovascular Disease (STROKE)
            STRUCT('G45.' AS icd_code, 9 AS icd_version, 1 AS weight, 'STROKE' AS comorbidity),
            STRUCT('G46.' AS icd_code, 9 AS icd_version, 1 AS weight, 'STROKE' AS comorbidity),
            STRUCT('I60.' AS icd_code, 9 AS icd_version, 1 AS weight, 'STROKE' AS comorbidity),
            -- Dementia (DEMENTIA)
            STRUCT('F00.' AS icd_code, 9 AS icd_version, 1 AS weight, 'DEMENTIA' AS comorbidity),
            STRUCT('F01.' AS icd_code, 9 AS icd_version, 1 AS weight, 'DEMENTIA' AS comorbidity),
            STRUCT('F02.' AS icd_code, 9 AS icd_version, 1 AS weight, 'DEMENTIA' AS comorbidity),
            STRUCT('F03.' AS icd_code, 9 AS icd_version, 1 AS weight, 'DEMENTIA' AS comorbidity),
            STRUCT('F05.1' AS icd_code, 9 AS icd_version, 1 AS weight, 'DEMENTIA' AS comorbidity),
            STRUCT('G30.' AS icd_code, 9 AS icd_version, 1 AS weight, 'DEMENTIA' AS comorbidity),
            STRUCT('G31.1' AS icd_code, 9 AS icd_version, 1 AS weight, 'DEMENTIA' AS comorbidity)
            -- ... (Continue for all other categories: COPD, RHEUM, PUD, LIVER, DIAB, DIABCX, HP, RENAL, CANCER, MSLDCANCER, METASTATIC, AIDS)
        ])
    ),
    -- Compute the Charlson score per hadm_id (sum weights for distinct comorbidities)
    charlson_score AS (
        SELECT
            diag.hadm_id,
            SUM(DISTINCT map.weight) AS charlson_score
        FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` diag
        INNER JOIN charlson_map map
            ON diag.icd_code = map.icd_code
            AND diag.icd_version = map.icd_version
        GROUP BY diag.hadm_id
    )
    SELECT
        c.hadm_id,
        COALESCE(cs.charlson_score, 0) AS charlson_score,
        CASE
            WHEN COALESCE(cs.charlson_score, 0) <= 3 THEN '<=3'
            WHEN COALESCE(cs.charlson_score, 0) BETWEEN 4 AND 5 THEN '4-5'
            ELSE '>5'
        END AS charlson_group
    FROM (SELECT DISTINCT hadm_id FROM cohort) c
    LEFT JOIN charlson_score cs
        ON c.hadm_id = cs.hadm_id
),

-- Identify mechanical ventilation
mech_vent AS (
    SELECT DISTINCT
        hadm_id
    FROM `physionet-data.mimiciv_3_1_icu.procedureevents` pe
    WHERE itemid IN (
        225792, 225794, 225795, 225796, 225797, 225798, 225799, 225800, 225801,  -- Mechanical ventilation
        225809, 225810, 225811, 225812, 225813, 225814, 225815, 225816           -- Additional vent codes
    )
),

-- Identify vasopressors
vasopressors AS (
    SELECT DISTINCT
        hadm_id
    FROM `physionet-data.mimiciv_3_1_icu.inputevents` ie
    WHERE itemid IN (
        221906,  -- Norepinephrine
        221289,  -- Epinephrine
        221662,  -- Dopamine
        221653,  -- Dobutamine
        221750,  -- Phenylephrine
        221749   -- Vasopressin
    )
),

-- Identify RRT
rrt AS (
    SELECT DISTINCT
        hadm_id
    FROM `physionet-data.mimiciv_3_1_icu.procedureevents` pe
    WHERE itemid IN (
        225802,  -- Continuous renal replacement therapy
        225803,  -- Intermittent hemodialysis
        225809,  -- Other dialysis
        225805   -- Peritoneal dialysis
    )
)

-- Main query: join cohort with Charlson and outcomes
SELECT
    c.icu_flag,
    c.los_group,
    ch.charlson_group,
    COUNT(*) AS n_admissions,
    -- In-hospital mortality
    SUM(c.hospital_expire_flag) AS n_mortality,
    ROUND(100.0 * SUM(c.hospital_expire_flag) / COUNT(*), 2) AS mortality_percent,
    -- Mechanical ventilation
    SUM(CASE WHEN mv.hadm_id IS NOT NULL THEN 1 ELSE 0 END) AS n_mech_vent,
    ROUND(100.0 * SUM(CASE WHEN mv.hadm_id IS NOT NULL THEN 1 ELSE 0 END) / COUNT(*), 2) AS mech_vent_percent,
    -- Vasopressors
    SUM(CASE WHEN vp.hadm_id IS NOT NULL THEN 1 ELSE 0 END) AS n_vasopressors,
    ROUND(100.0 * SUM(CASE WHEN vp.hadm_id IS NOT NULL THEN 1 ELSE 0 END) / COUNT(*), 2) AS vasopressors_percent,
    -- RRT
    SUM(CASE WHEN rt.hadm_id IS NOT NULL THEN 1 ELSE 0 END) AS n_rrt,
    ROUND(100.0 * SUM(CASE WHEN rt.hadm_id IS NOT NULL THEN 1 ELSE 0 END) / COUNT(*), 2) AS rrt_percent
FROM cohort c
LEFT JOIN charlson ch
    ON c.hadm_id = ch.hadm_id
LEFT JOIN mech_vent mv
    ON c.hadm_id = mv.hadm_id
LEFT JOIN vasopressors vp
    ON c.hadm_id = vp.hadm_id
LEFT JOIN rrt rt
    ON c.hadm_id = rt.hadm_id
GROUP BY c.icu_flag, c.los_group, ch.charlson_group
ORDER BY c.icu_flag, c.los_group, ch.charlson_group;