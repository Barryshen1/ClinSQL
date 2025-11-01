WITH pe_cohort AS (
    SELECT DISTINCT
        adm.subject_id,
        adm.hadm_id,
        adm.admittime,
        adm.dischtime,
        adm.deathtime,
        adm.hospital_expire_flag,
        pat.anchor_age,
        eq.elixhauser_vanwalraven AS comorbidity_score,
        -- 30-day mortality: death within 30 days of admission
        CASE WHEN adm.deathtime IS NOT NULL 
             AND DATE_DIFF(DATE(adm.deathtime), DATE(adm.admittime), DAY) <= 30 
             THEN 1 ELSE 0 END AS mortality_30day,
        -- LOS for survivors only
        CASE WHEN adm.hospital_expire_flag = 0 
             THEN DATE_DIFF(DATE(adm.dischtime), DATE(adm.admittime), DAY) 
             ELSE NULL END AS los_survivors,
        -- Cardio complications: presence of relevant ICD codes
        MAX(CASE WHEN (diag.icd_code LIKE 'I21%' OR diag.icd_code LIKE 'I22%' 
                  OR diag.极d_code LIKE 'I44%' OR diag.icd_code LIKE 'I45%' 
                  OR diag.icd_code LIKE 'I46%' OR diag.icd_code LIKE 'I47%' 
                  OR diag.icd_code LIKE 'I48%' OR diag.icd_code LIKE 'I49%' 
                  OR diag.icd_code LIKE 'I50%') AND diag.icd_version = 10
                  OR (diag.icd_code LIKE '410%' OR diag.icd_code LIKE '411%'
                  OR diag.icd_code LIKE '426%' OR diag.icd_code LIKE '427%'
                  OR diag.icd_code LIKE '428%') AND diag.icd_version = 9
             THEN 1 ELSE 0 END) AS cardio_complication,
        -- Neurologic complications
        MAX(CASE WHEN (diag.icd_code LIKE 'G45%' OR diag.icd_code LIKE 'G46%' 
                  OR diag.icd_code LIKE 'I60%' OR diag.icd_code LIKE 'I61%' 
                  OR diag.icd_code LIKE 'I62%' OR diag.icd_code LIKE 'I63%' 
                  OR diag.icd_code LIKE 'I64%' OR diag.icd_code LIKE 'I65%' 
                  OR diag.icd_code LIKE 'I66%' OR diag.icd_code LIKE 'I67%' 
                  OR diag.icd_code LIKE 'I68%' OR diag.icd_code LIKE 'I69%') AND diag.icd_version = 10
                  OR (diag.icd_code LIKE '430%' OR diag.icd_code LIKE '431%'
                  OR diag.icd_code LIKE '432%' OR diag.icd_code LIKE '433%'
                  OR diag.icd_code LIKE '434%' OR diag.icd_code LIKE '435%'
                  OR diag.icd_code LIKE '436%' OR diag.icd_code LIKE '437%'
                  OR diag.icd_code LIKE '438%') AND diag.icd_version = 9
             THEN 1 ELSE 0 END) AS neurologic_complication
    FROM `physionet-data.mimiciv_3_1_hosp.admissions` adm
    INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` pat
        ON adm.subject_id = pat.subject_id
    INNER JOIN `physionet-data.mimiciv_3_1_hosp.elixhauser_quan` eq
        ON adm.hadm_id = eq.hadm_id
    INNER JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` diag_pe
        ON adm.hadm_id = diag_pe.hadm_id
    LEFT JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` diag
        ON adm.hadm_id = diag.hadm_id
    WHERE pat.gender = 'F'
        AND pat.anchor_age BETWEEN 59 AND 69
        AND ((diag_pe.icd_code LIKE 'I26%' AND diag_pe.icd_version = 10)  -- Pulmonary embolism ICD-10
             OR (diag_pe.icd_code LIKE '415.1%' AND diag_pe.icd_version = 9))  -- Pulmonary embolism ICD-9
    GROUP BY adm.subject_id, adm.hadm_id, adm.admittime, adm.dischtime, 
             adm.deathtime, adm.hospital_expire_flag, pat.anchor_age, 
             eq.elixhauser_vanwalraven
),

control_cohort AS (
    SELECT 
        adm.subject_id,
        adm.hadm_id,
        adm.admittime,
        adm.dischtime,
        adm.deathtime,
        adm.hospital_expire_flag,
        pat.anchor_age,
        eq.elixhauser_vanwalraven AS comorbidity_score,
        CASE WHEN adm.deathtime IS NOT NULL 
             AND DATE_DIFF(DATE(adm.deathtime), DATE(adm.admittime), DAY) <= 30 
             THEN 1 ELSE 0 END AS mortality_30day,
        CASE WHEN adm.hospital_expire_flag = 0 
             THEN DATE_DIFF(DATE(adm.dischtime), DATE(adm.admittime), DAY) 
             ELSE NULL END AS los_survivors,
        MAX(CASE WHEN (diag.icd_code LIKE 'I21%' OR diag.icd_code LIKE 'I22%' 
                  OR diag.icd_code LIKE 'I44%' OR diag.icd_code LIKE 'I45%' 
                  OR diag.icd_code LIKE 'I46%' OR diag.icd_code LIKE 'I47%' 
                  OR diag.icd_code LIKE '极48%' OR diag.icd_code LIKE 'I49%' 
                  OR diag.icd_code LIKE 'I50%') AND diag.icd_version = 10
                  OR (diag.icd_code LIKE '410%' OR diag.icd_code LIKE '411%'
                  OR diag.icd_code LIKE '426%' OR diag.icd_code LIKE '427%'
                  OR diag.icd_code LIKE '428%') AND diag.icd_version = 9
             THEN 1 ELSE 0 END) AS cardio_complication,
        MAX(CASE WHEN (diag.icd_code LIKE 'G45%' OR diag.icd_code LIKE 'G46%' 
                  OR diag.icd_code LIKE 'I60%' OR diag.icd_code LIKE 'I61%' 
                  OR diag.icd_code LIKE 'I62%' OR diag.icd_code LIKE 'I63%' 
                  OR diag.icd_code LIKE 'I64%' OR diag.icd_code LIKE 'I65%' 
                  OR diag.icd_code LIKE 'I66%' OR diag.icd_code LIKE 'I67%' 
                  OR diag.icd_code LIKE 'I68%' OR diag.icd_code LIKE 'I69%') AND diag.icd_version = 10
                  OR (diag.icd_code LIKE '430%' OR diag.icd_code LIKE '431%'
                  OR diag.icd_code LIKE '432%' OR diag.icd_code LIKE '433%'
                  OR diag.icd_code LIKE '434%' OR diag.icd_code LIKE '435%'
                  OR diag.icd_code LIKE '436%' OR diag.icd_code LIKE '437%'
                  OR diag.icd_code LIKE '438%') AND diag.icd_version = 9
             THEN 1 ELSE 0 END) AS neurologic_complication
    FROM `physionet-data.mimiciv_3_1_hosp.admissions` adm
    INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` pat
        ON adm.subject_id = pat.subject_id
    INNER JOIN `physionet-data.mimiciv_3_1_hosp.elixhauser_quan` eq
        ON adm.hadm_id = eq.hadm_id
    LEFT JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` diag
        ON adm.hadm_id = diag.hadm_id
    WHERE pat.gender = 'F'
        AND pat.anchor_age BETWEEN 59 AND 69
        -- Exclude PE patients to make control group
        AND adm.hadm_id NOT IN (SELECT hadm_id FROM pe_cohort)
    GROUP BY adm.subject_id, adm.hadm_id, adm.admittime, adm.dischtime, 
             adm.deathtime, adm.hospital_expire_flag, pat.anchor_age, 
             eq.elixhauser_vanwalraven
),

pe_summary AS (
    SELECT
        'PE Cohort' AS cohort,
        COUNT(*) AS n_patients,
        AVG(comorbidity_score) AS mean_comorbidity_score,
        AVG(CAST(mortality_30day AS FLOAT64)) AS mortality_30day_rate,
        AVG(CAST(cardio_complication AS FLOAT64)) AS cardio_complication_rate,
        AVG(CAST(neurologic_complication AS FLOAT64)) AS neurologic_complication_rate,
        AVG(los_survivors) AS mean_los_survivors
    FROM pe_cohort
),

control_summary AS (
    SELECT
        'Control Cohort' AS cohort,
        COUNT(*) AS n_patients,
        AVG(comorbidity_score) AS mean_comorbidity_score,
        AVG(CAST(mortality_30day AS FLOAT64)) AS mortality_30day_rate,
        AVG(CAST(cardio_complication AS FLOAT64)) AS cardio_complication_rate,
        AVG(CAST(neurologic_complication AS FLOAT64)) AS neurologic_complication_rate,
        AVG(los_survivors) AS mean_los_survivors
    FROM control_cohort
),

percentile_calc AS (
    SELECT
        pc.hadm_id,
        pc.comorbidity_score,
        PERCENT_RANK() OVER (ORDER BY cc.comorbidity_score) AS percentile_rank
    FROM pe_cohort pc
    CROSS JOIN control_cohort cc
)

SELECT 
    p.cohort,
    p.n_patients,
    p.mean_comorbidity_score,
    p.mortality_30day_rate,
    p.cardio_complication_rate,
    p.neurologic_complication_rate,
    p.mean_los_survivors,
    c.mean_comorbidity_score AS control_mean_comorbidity_score,
    c.mortality_30day_rate AS control_mortality_30day_rate,
    c.cardio_complication_rate AS control_cardio_complication_rate,
    c.neurologic_complication_rate AS control_neurologic_complication_rate,
    c.mean_los_survivors AS control_mean_los_survivors,
    (SELECT AVG(percentile_rank) FROM percentile_calc) AS avg_comorbidity_percentile_vs_controls
FROM pe_summary p
CROSS JOIN control_summary c;