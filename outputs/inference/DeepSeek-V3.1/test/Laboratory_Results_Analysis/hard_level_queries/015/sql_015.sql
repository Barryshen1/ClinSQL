WITH stroke_cohort AS (
    SELECT 
        adm.subject_id, 
        adm.hadm_id, 
        adm.admittime, 
        adm.dischtime,
        adm.hospital_expire_flag,
        DATETIME_DIFF(adm.dischtime, adm.admittime, HOUR) / 24.0 AS los_days,
        pat.anchor_age
    FROM `physionet-data.mimiciv_3_1_hosp.admissions` adm
    INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` pat
        ON adm.subject_id = pat.subject_id
    WHERE pat.gender = 'M'
        AND pat.anchor_age BETWEEN 49 AND 59
        AND EXISTS (
            SELECT 1
            FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` diag
            WHERE adm.subject_id = diag.subject_id
                AND adm.hadm_id = diag.hadm_id
                AND (
                    (diag.icd_version = 10 AND diag.icd_code LIKE 'I63%')
                    OR (diag.icd_version = 9 AND (diag.icd_code LIKE '433%' OR diag.icd_code LIKE '434%' OR diag.icd_code = '436'))
                )
        )
),

-- Get labs in first 72 hours for stroke cohort
labs_72hr AS (
    SELECT 
        le.subject_id,
        le.hadm_id,
        le.itemid,
        le.valuenum,
        le.charttime
    FROM `physionet-data.mimiciv_3_1_hosp.labevents` le
    INNER JOIN stroke_cohort coh
        ON le.subject_id = coh.subject_id
        AND le.hadm_id = coh.hadm_id
    WHERE le.charttime BETWEEN coh.admittime AND DATETIME_ADD(coh.admittime, INTERVAL 72 HOUR)
        AND le.valuenum IS NOT NULL
        AND le.itemid IN (
            -- Sodium
            50824,
            -- Potassium
            50822,
            -- Glucose
            50820,
            -- Creatinine
            50912,
            -- Hemoglobin
            51222,
            -- White blood cells
            51300
        )
),

-- For each patient and lab, get the worst value (min or max depending on direction)
lab_thresholds AS (
    SELECT 
        subject_id,
        hadm_id,
        -- Sodium: critical <120 or >160
        MAX(CASE WHEN itemid = 50824 AND (valuenum < 120 OR valuenum > 160) THEN 1 ELSE 0 END) AS sodium_critical,
        -- Potassium: critical <2.5 or >6
        MAX(CASE WHEN itemid = 50822 AND (valuenum < 2.5 OR valuenum > 6) THEN 1 ELSE 0 END) AS potassium_critical,
        -- Glucose: critical <50 or >400
        MAX(CASE WHEN itemid = 50820 AND (valuenum < 50 OR valuenum > 400) THEN 1 ELSE 0 END) AS glucose_critical,
        -- Creatinine: critical >4
        MAX(CASE WHEN itemid = 50912 AND valuenum > 4 THEN 1 ELSE 0 END) AS creatinine_critical,
        -- Hemoglobin: critical <7
        MAX(CASE WHEN itemid = 51222 AND valuenum < 7 THEN 1 ELSE 0 END) AS hemoglobin_critical,
        -- White blood cells: critical <1 or >50
        MAX(CASE WHEN itemid = 51300 AND (valuenum < 1 OR valuenum > 50) THEN 1 ELSE 0 END) AS wbc_critical
    FROM labs_72hr
    GROUP BY subject_id, hadm_id
),

-- Compute instability score per patient (sum of critical labs)
instability_scores AS (
    SELECT 
        subject_id,
        hadm_id,
        COALESCE(sodium_critical, 0) 
        + COALESCE(potassium_critical, 0) 
        + COALESCE(glucose_critical, 0) 
        + COALESCE(creatinine_critical, 0) 
        + COALESCE(hemoglobin_critical, 0) 
        + COALESCE(wbc_critical, 0) AS instability_score
    FROM lab_thresholds
),

-- Get the 75th percentile of instability score
p75_score AS (
    SELECT 
        APPROX_QUANTILES(instability_score, 100)[OFFSET(75)] AS p75
    FROM instability_scores
),

-- High-instability group
high_instability_group AS (
    SELECT 
        coh.*,
        ins.instability_score
    FROM stroke_cohort coh
    LEFT JOIN instability_scores ins
        ON coh.subject_id = ins.subject_id
        AND coh.hadm_id = ins.hadm_id
    CROSS JOIN p75_score
    WHERE ins.instability_score >= p75_score.p75
),

-- Control group: male inpatients aged 49-59 without ischemic stroke
control_group AS (
    SELECT 
        adm.subject_id, 
        adm.hadm_id, 
        adm.admittime, 
        adm.dischtime
    FROM `physionet-data.mimiciv_3_1_hosp.admissions` adm
    INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` pat
        ON adm.subject_id = pat.subject_id
    WHERE pat.gender = 'M'
        AND pat.anchor_age BETWEEN 49 AND 59
        AND NOT EXISTS (
            SELECT 1
            FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` diag
            WHERE adm.subject_id = diag.subject_id
                AND adm.hadm_id = diag.hadm_id
                AND (
                    (diag.icd_version = 10 AND diag.icd_code LIKE 'I63%')
                    OR (diag.icd_version = 9 AND (diag.icd_code LIKE '433%' OR diag.icd_code LIKE '434%' OR diag.icd_code = '436'))
                )
        )
),

-- Get all labs for control group (entire stay)
control_labs AS (
    SELECT 
        le.subject_id,
        le.hadm_id,
        le.itemid,
        le.valuenum
    FROM `physionet-data.mimiciv_3_1_hosp.labevents` le
    INNER JOIN control_group coh
        ON le.subject_id = coh.subject_id
        AND le.hadm_id = coh.hadm_id
    WHERE le.valuenum IS NOT NULL
        AND le.itemid IN (50824, 50822, 50820, 50912, 51222, 51300)
),

-- For control group, mark critical labs per patient
control_critical_labs AS (
    SELECT 
        subject_id,
        hadm_id,
        -- Sodium
        MAX(CASE WHEN itemid = 50824 AND (valuenum < 120 OR valuenum > 160) THEN 1 ELSE 0 END) AS sodium_critical,
        -- Potassium
        MAX(CASE WHEN itemid = 50822 AND (valuenum < 2.5 OR valuenum > 6) THEN 1 ELSE 0 END) AS potassium_critical,
        -- Glucose
        MAX(CASE WHEN itemid = 50820 AND (valuenum < 50 OR valuenum > 400) THEN 1 ELSE 0 END) AS glucose_critical,
        -- Creatinine
        MAX(CASE WHEN itemid = 50912 AND valuenum > 4 THEN 1 ELSE 0 END) AS creatinine_critical,
        -- Hemoglobin
        MAX(CASE WHEN itemid = 51222 AND valuenum < 7 THEN 1 ELSE 0 END) AS hemoglobin_critical,
        -- White blood cells
        MAX(CASE WHEN itemid = 51300 AND (valuenum < 1 OR valuenum > 50) THEN 1 ELSE 0 END) AS wbc_critical
    FROM control_labs
    GROUP BY subject_id, hadm_id
),

-- Similarly, get all labs for high_instability_group (entire stay)
high_instability_labs AS (
    SELECT 
        le.subject_id,
        le.hadm_id,
        le.itemid,
        le.valuenum
    FROM `physionet-data.mimiciv_3_1_hosp.labevents` le
    INNER JOIN high_instability_group coh
        ON le.subject_id = coh.subject_id
        AND le.hadm_id = coh.hadm_id
    WHERE le.valuenum IS NOT NULL
        AND le.itemid IN (50824, 50822, 50820, 50912, 51222, 51300)
),

-- For high instability group, mark critical labs per patient
high_instability_critical_labs AS (
    SELECT 
        subject_id,
        hadm_id,
        MAX(CASE WHEN itemid = 50824 AND (valuenum < 120 OR valuenum > 160) THEN 1 ELSE 0 END) AS sodium_critical,
        MAX(CASE WHEN itemid = 50822 AND (valuenum < 2.5 OR valuenum > 6) THEN 1 ELSE 0 END) AS potassium_critical,
        MAX(CASE WHEN itemid = 50820 AND (valuenum < 50 OR valuenum > 400) THEN 1 ELSE 0 END) AS glucose_critical,
        MAX(CASE WHEN itemid = 50912 AND valuenum > 4 THEN 1 ELSE 0 END) AS creatinine_critical,
        MAX(CASE WHEN itemid = 51222 AND valuenum < 7 THEN 1 ELSE 0 END) AS hemoglobin_critical,
        MAX(CASE WHEN itemid = 51300 AND (valuenum < 1 OR valuenum > 50) THEN 1 ELSE 0 END) AS wbc_critical
    FROM high_instability_labs
    GROUP BY subject_id, hadm_id
)

-- Final output
SELECT 
    -- 75th percentile score
    (SELECT p75 FROM p75_score) AS p75_instability_score,

    -- High-instability group summary
    (SELECT COUNT(*) FROM high_instability_group) AS high_instability_count,
    (SELECT AVG(los_days) FROM high_instability_group) AS avg_los_high_instability,
    (SELECT AVG(hospital_expire_flag) FROM high_instability_group) AS mortality_rate_high_instability,

    -- Critical lab rates in high-instability group
    (SELECT AVG(sodium_critical) FROM high_instability_critical_labs) AS high_instability_sodium_critical_rate,
    (SELECT AVG(potassium_critical) FROM high_instability_critical_labs) AS high_instability_potassium_critical_rate,
    (SELECT AVG(glucose_critical) FROM high_instability_critical_labs) AS high_instability_glucose_critical_rate,
    (SELECT AVG(creatinine_critical) FROM high_instability_critical_labs) AS high_instability_creatinine_critical_rate,
    (SELECT AVG(hemoglobin_critical) FROM high_instability_critical_labs) AS high_instability_hemoglobin_critical_rate,
    (SELECT AVG(wbc_critical) FROM high_instability_critical_labs) AS high_instability_wbc_critical_rate,

    -- Critical lab rates in control group
    (SELECT AVG(sodium_critical) FROM control_critical_labs) AS control_sodium_critical_rate,
    (SELECT AVG(potassium_critical) FROM control_critical_labs) AS control_potassium_critical_rate,
    (SELECT AVG(glucose_critical) FROM control_critical_labs) AS control_glucose_critical_rate,
    (SELECT AVG(creatinine_critical) FROM control_critical_labs) AS control_creatinine_critical_rate,
    (SELECT AVG(hemoglobin_critical) FROM control_critical_labs) AS control_hemoglobin_critical_rate,
    (SELECT AVG(wbc_critical) FROM control_critical_labs) AS control_wbc_critical_rate;