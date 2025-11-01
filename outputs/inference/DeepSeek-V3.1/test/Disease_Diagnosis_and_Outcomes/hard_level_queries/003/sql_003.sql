WITH base_cohort AS (
    -- All female inpatients aged 70-80
    SELECT 
        adm.subject_id,
        adm.hadm_id,
        adm.admittime,
        adm.dischtime,
        adm.deathtime,
        pt.dod,
        pt.anchor_age,
        DATETIME_DIFF(adm.dischtime, adm.admittime, DAY) AS los_days,
        -- Flag for PE
        CASE WHEN EXISTS (
            SELECT 1
            FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` dx
            WHERE dx.hadm_id = adm.hadm_id
                AND ((dx.icd_version = 9 AND dx.icd_code LIKE '4151%')
                OR (dx.icd_version = 10 AND dx.icd_code LIKE 'I26%'))
        ) THEN 1 ELSE 0 END AS has_pe
    FROM `physionet-data.mimiciv_3_1_hosp.admissions` adm
    INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` pt
        ON adm.subject_id = pt.subject_id
    WHERE pt.gender = 'F'
        AND pt.anchor_age BETWEEN 70 AND 80
),

-- Calculate Elixhauser comorbidity score for PE patients
pe_risk AS (
    SELECT 
        bc.subject_id,
        bc.hadm_id,
        bc.admittime,
        bc.dischtime,
        bc.deathtime,
        bc.dod,
        bc.los_days,
        -- Count distinct Elixhauser comorbidities (simplified approach)
        COUNT(DISTINCT 
            CASE WHEN dx.icd_version = 9 AND dx.icd_code LIKE '428%' THEN 'CHF'
                 WHEN dx.icd_version = 10 AND dx.icd_code LIKE 'I50%' THEN 'CHF'
                 WHEN dx.icd_version = 9 AND dx.icd_code LIKE '410%' THEN 'Valvular'
                 WHEN dx.icd_version = 10 AND dx.icd_code LIKE 'I0[0-8]%' THEN 'Valvular'
                 -- Add more comorbidity conditions as needed
            END
        ) AS comorbidity_score
    FROM base_cohort bc
    LEFT JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` dx
        ON bc.hadm_id = dx.hadm_id
    WHERE bc.has_pe = 1
    GROUP BY bc.subject_id, bc.hadm_id, bc.admittime, bc.dischtime, bc.deathtime, bc.dod, bc.los_days
),

-- Stratify into quintiles based on comorbidity_score
pe_risk_quintiles AS (
    SELECT *,
        NTILE(5) OVER (ORDER BY comorbidity_score) AS risk_quintile
    FROM pe_risk
),

-- Identify AKI during the admission
aki_dx AS (
    SELECT 
        hadm_id,
        1 AS aki_flag
    FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd`
    WHERE 
        (icd_version = 9 AND icd_code LIKE '584%')
        OR (icd_version = 10 AND icd_code LIKE 'N17%')
    GROUP BY hadm_id
),

-- Identify ARDS during the admission
ards_dx AS (
    SELECT 
        hadm_id,
        1 AS ards_flag
    FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd`
    WHERE 
        (icd_version = 9 AND icd_code = '518.82')
        OR (icd_version = 10 AND icd_code = 'J80')
    GROUP BY hadm_id
),

-- Calculate survivor status for median LOS calculation
cohort_with_outcomes AS (
    SELECT 
        COALESCE(prq.risk_quintile, 0) AS risk_quintile,
        COALESCE(prq.subject_id, bc.subject_id) AS subject_id,
        COALESCE(prq.hadm_id, bc.hadm_id) AS hadm_id,
        COALESCE(prq.admittime, bc.admittime) AS admittime,
        COALESCE(prq.dischtime, bc.dischtime) AS dischtime,
        COALESCE(prq.dod, bc.dod) AS dod,
        COALESCE(prq.los_days, bc.los_days) AS los_days,
        COALESCE(aki.aki_flag, 0) AS aki_flag,
        COALESCE(ards.ards_flag, 0) AS ards_flag,
        CASE WHEN bc.has_pe = 1 THEN 1'PE' ELSE '0Comparison' END AS cohort_type,
        CASE WHEN DATETIME_DIFF(COALESCE(prq.dod, bc.dod), COALESCE(prq.admittime, bc.admittime), DAY) <= 90 
             THEN 1 ELSE 0 END AS died_90d
    FROM base_cohort bc
    LEFT JOIN pe_risk_quintiles prq ON bc.hadm_id = prq.hadm_id
    LEFT JOIN aki_dx aki ON bc.hadm_id = aki.hadm_id
    LEFT JOIN ards_dx ards ON bc.hadm_id = ards.hadm_id
)

-- Main results
SELECT 
    CASE WHEN cohort_type = '0Comparison' THEN 'Comparison (all 70-80 F)'
         ELSE CAST(risk_quintile AS STRING) END AS risk_quintile,
    COUNT(*) AS n_admissions,
    SUM(died_90d) AS deaths_90d,
    AVG(died_90d) * 100 AS mortality_90d_pct,
    AVG(aki_flag) * 100 AS aki_rate_pct,
    AVG(ards_flag) * 100 AS ards_rate_pct,
    APPROX_QUANTILES(
        CASE WHEN died_90d = 0 THEN los_days END, 
        2
    )[OFFSET(1)] AS median_survivor_los_days
FROM cohort_with_outcomes
WHERE cohort_type = '1PE' OR (cohort_type = '0Comparison' AND has_pe = 0)
GROUP BY risk_quintile, cohort_type
ORDER BY cohort_type, risk_quintile;