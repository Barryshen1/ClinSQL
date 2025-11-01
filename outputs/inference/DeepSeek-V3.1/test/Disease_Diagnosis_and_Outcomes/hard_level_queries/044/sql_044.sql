WITH cardiac_arrest_cohort AS (
    SELECT 
        adm.subject_id,
        adm.hadm_id,
        adm.admittime,
        adm.dischtime,
        pat.dod,
        -- Placeholder for risk score (not defined)
        NULL AS risk_score,
        -- Check for cardiovascular complications: myocardial infarction (I21, I22), heart failure (I50)
        MAX(CASE WHEN diag.icd_code LIKE 'I21%' OR diag.icd_code LIKE 'I22%' OR diag.icd_code LIKE 'I50%' THEN 1 ELSE 0 END) AS cardiovascular_complication,
        -- Neurologic complications: stroke (I63)
        MAX(CASE WHEN diag.icd_code LIKE 'I63%' THEN 1 ELSE 0 END) AS neurologic_complication
    FROM `physionet-data.mimiciv_3_1_hosp.admissions` adm
    INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` pat
        ON adm.subject_id = pat.subject_id
    INNER JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` diag
        ON adm.subject_id = diag.subject_id AND adm.hadm_id = diag.hadm_id
    WHERE pat.gender = 'F'
        AND pat.anchor_age BETWEEN 59 AND 69
        AND diag.icd_code LIKE 'I46%'  -- Cardiac arrest
    GROUP BY adm.subject_id, adm.hadm_id, adm.admittime, adm.dischtime, pat.dod
),
cohort_with_outcomes AS (
    SELECT 
        subject_id,
        hadm_id,
        risk_score,
        cardiovascular_complication,
        neurologic_complication,
        -- 30-day mortality: death within 30 days of admission
        CASE WHEN dod <= DATETIME_ADD(admittime, INTERVAL 30 DAY) THEN 1 ELSE 0 END AS mortality_30day,
        -- LOS for survivors: only those who did not die in hospital (using dischtime and deathtime would be better, but we use dod for out-of-hospital too)
        -- Actually, we use dischtime and admittime for LOS, and only for those who survived (mortality_30day=0)
        DATETIME_DIFF(dischtime, admittime, DAY) AS los_days
    FROM cardiac_arrest_cohort
),
baseline_cohort AS (
    SELECT 
        adm.subject_id,
        adm.hadm_id,
        adm.admittime,
        pat.dod
    FROM `physionet-data.mimiciv_3_1_hosp.admissions` adm
    INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` pat
        ON adm.subject_id = pat.subject_id
    WHERE pat.gender = 'F'
        AND pat.anchor_age BETWEEN 59 AND 69
        -- Exclude cardiac arrest diagnoses
        AND NOT EXISTS (
            SELECT 1 
            FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` diag 
            WHERE diag.subject_id = adm.subject_id 
                AND diag.hadm_id = adm.hadm_id 
                AND diag.icd_code LIKE 'I46%'
        )
),
baseline_outcomes AS (
    SELECT
        -- 30-day mortality for baseline
        CASE WHEN dod <= DATETIME_ADD(admittime, INTERVAL 30 DAY) THEN 1 ELSE 0 END AS mortality_30day
    FROM baseline_cohort
)
-- Aggregate the cardiac arrest cohort (without quartiles) and baseline
SELECT
    'Cardiac Arrest Cohort' AS cohort,
    COUNT(*) AS n_patients,
    AVG(mortality_30day) AS mortality_30day_rate,
    AVG(cardiovascular_complication) AS cardiovascular_complication_rate,
    AVG(neurologic_complication) AS neurologic_complication_rate,
    -- Median LOS for survivors
    APPROX_QUANTILES(los_days, 100) [OFFSET(50)] AS median_los_survivors,
    NULL AS baseline_mortality_30day
FROM cohort_with_outcomes
WHERE mortality_30day = 0  -- Only survivors for LOS
UNION ALL
SELECT
    'Baseline (All Female 59-69)' AS cohort,
    COUNT(*) AS n_patients,
    NULL AS mortality_30day_rate,
    NULL AS cardiovascular_complication_rate,
    NULL AS neurologic_complication_rate,
    NULL AS median_los_survivors,
    AVG(mortality_30day) AS baseline_mortality_30day
FROM baseline_outcomes;