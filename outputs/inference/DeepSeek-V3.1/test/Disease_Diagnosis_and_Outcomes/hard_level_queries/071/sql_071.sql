WITH ami_cohort AS (
    SELECT DISTINCT
        p.subject_id,
        p.gender,
        p.anchor_age as age,
        a.hadm_id,
        a.admittime,
        a.dischtime,
        a.deathtime,
        i.stay_id,
        i.intime as icu_intime,
        i.outtime as icu_outtime,
        -- Calculate 90-day mortality
        CASE WHEN DATETIME_DIFF(COALESCE(a.deathtime, p.dod), a.admittime, DAY) <= 90 THEN 1 ELSE 0 END AS mortality_90day,
        -- LOS for survivors
        CASE WHEN a.hospital_expire_flag = 0 THEN DATETIME_DIFF(a.dischtime, a.admittime, DAY) ELSE NULL END AS los_hospital
    FROM `physionet-data.mimiciv_3_1_hosp.patients` p
    INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a
        ON p.subject_id = a.subject_id
    INNER JOIN `physionet-data.mimiciv_3_1_icu.icustays` i
        ON a.hadm_id = i.hadm_id
    INNER JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
        ON a.hadm_id = d.hadm_id
    WHERE p.gender = 'F'
        AND p.anchor_age BETWEEN 68 AND 78
        AND (d.icd_code LIKE 'I21%' OR d.icd_code LIKE 'I22%')
        AND d.icd_version = 10
),
-- Calculate risk score (simplified: using age only as placeholder)
risk_scores AS (
    SELECT 
        subject_id,
        hadm_id,
        age as risk_score,
        -- Percentile within AMI cohort
        PERCENTILE_CONT(age, 0.5) OVER() AS median_risk,
        PERCENTILE_CONT(age, 0.25) OVER() AS q1_risk,
        PERCENTILE_CONT(age, 0.75) OVER() AS q3_risk,
        mortality_90day,
        los_hospital
    FROM ami_cohort
),
-- Major complications: define with ICD codes (example: cardiogenic shock R57.0)
complications AS (
    SELECT 
        hadm_id,
        MAX(CASE WHEN icd_code = 'R570' AND icd_version=10 THEN 1 ELSE 0 END) as comp_cardiac_shock
    FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd`
    GROUP BY hadm_id
),
ami_with_complications AS (
    SELECT 
        r.*,
        COALESCE(c.comp_cardiac_shock,0) as major_complication
    FROM risk_scores r
    LEFT JOIN complications c
        ON r.hadm_id = c.hadm_id
),
-- Control group: females aged 68-78 with ICU stay but without AMI
control_group AS (
    SELECT DISTINCT
        p.subject_id,
        p.gender,
        p.anchor_age as age,
        a.hadm_id,
        a.admittime,
        a.dischtime,
        a.deathtime,
        i.stay_id,
        i.intime as icu_intime,
        i.outtime as icu_outtime,
        CASE WHEN DATETIME_DIFF(COALESCE(a.deathtime, p.dod), a.admittime, DAY) <= 90 THEN 1 ELSE 0 END AS mortality_90day,
        CASE WHEN a.hospital_expire_flag = 0 THEN DATETIME_DIFF(a.dischtime, a.admittime, DAY) ELSE NULL END AS los_hospital
    FROM `physionet-data.mimiciv_3_1_hosp.patients` p
    INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a
        ON p.subject_id = a.subject_id
    INNER JOIN `physionet-data.mimiciv_3_1_icu.icustays` i
        ON a.hadm_id = i.hadm_id
    WHERE p.gender = 'F'
        AND p.anchor_age BETWEEN 68 AND 78
        AND a.hadm_id NOT IN (
            SELECT hadm_id 
            FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` 
            WHERE (icd_code LIKE 'I21%' OR icd_code LIKE 'I22%') 
            AND icd_version = 10
        )
),
control_complications AS (
    SELECT 
        c.hadm_id,
        c.mortality_90day,
        COALESCE(comp.comp_cardiac_shock,0) as major_complication,
        c.los_hospital
    FROM control_group c
    LEFT JOIN complications comp
        ON c.hadm_id = comp.hadm_id
)
-- Final output
SELECT 
    'AMI Cohort' as cohort,
    COUNT(*) as n_patients,
    AVG(risk_score) as mean_risk_score,
    MIN(risk_score) as min_risk,
    MAX(risk_score) as max_risk,
    -- Median and IQR
    APPROX_QUANTILES(risk_score, 100)[OFFSET(50)] as median_risk,
    APPROX_QUANTILES(risk_score, 100)[OFFSET(25)] as q1_risk,
    APPROX_QUANTILES(risk_score, 100)[OFFSET(75)] as q3_risk,
    AVG(mortality_90day) as mortality_90day_rate,
    AVG(major_complication) as major_complication_rate,
    AVG(los_hospital) as avg_survivor_los
FROM ami_with_complications

UNION ALL

SELECT 
    'Control Group' as cohort,
    COUNT(*) as n_patients,
    NULL as mean_risk_score,
    NULL as min_risk,
    NULL as max_risk,
    NULL as median_risk,
    NULL as q1_risk,
    NULL as q3_risk,
    AVG(mortality_90day) as mortality_90day_rate,
    AVG(major_complication) as major_complication_rate,
    AVG(los_hospital) as avg_survivor_los
FROM control_complications;