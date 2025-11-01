WITH
-- Target cohort: ACS patients with ICU stay, female, age 67-77
target_cohort AS (
    SELECT DISTINCT
        a.subject_id,
        a.hadm_id,
        a.admittime,
        a.dischtime,
        a.hospital_expire_flag,
        p.dod,
        -- LOS in days
        DATETIME_DIFF(a.dischtime, a.admittime, DAY) AS los_hospital,
        -- 30-day mortality
        CASE WHEN p.dod IS NOT NULL AND p.dod <= DATETIME_ADD(a.admittime, INTERVAL 30 DAY) THEN 1 ELSE 0 END AS mortality_30d
    FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
    INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
        ON a.subject_id = p.subject_id
    INNER JOIN `physionet-data.mimiciv_3_1_icu.icustays` icu
        ON a.hadm_id = icu.hadm_id
    WHERE p.gender = 'F'
        AND p.anchor_age BETWEEN 67 AND 77
        AND a.hadm_id IN (
            SELECT hadm_id
            FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd`
            WHERE 
                (icd_version = 9 AND (icd_code LIKE '410%' OR icd_code LIKE '411%')) OR
                (icd_version = 10 AND (icd_code LIKE 'I21%' OR icd_code LIKE 'I22%' OR icd_code LIKE 'I24%'))
        )
),

-- Cardiac complications (ICD9: 427,428; ICD10: I46,I47,I48,I49,I50)
cardiac_complications AS (
    SELECT hadm_id
    FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd`
    WHERE 
        (icd_version = 9 AND (icd_code LIKE '427%' OR icd_code LIKE '428%')) OR
        (icd_version = 10 AND (icd_code LIKE 'I46%' OR icd_code LIKE 'I47%' OR icd_code LIKE 'I48%' OR icd_code LIKE 'I49%' OR icd_code LIKE 'I50%'))
),

-- Neurologic complications (ICD9: 430-438; ICD10: I60-I69, F05, G40)
neuro_complications AS (
    SELECT hadm_id
    FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd`
    WHERE 
        (icd_version = 9 AND (icd_code BETWEEN '430' AND '438')) OR
        (icd_version = 10 AND (
            icd_code LIKE 'I6%' OR 
            icd_code = 'F05' OR 
            icd_code LIKE 'G40%'
        ))
),

-- Control cohort: all female inpatients aged 67-77
control_cohort AS (
    SELECT
        a.subject_id,
        a.hadm_id,
        a.admittime,
        a.dischtime,
        a.hospital_expire_flag,
        p.dod,
        DATETIME_DIFF(a.dischtime, a.admittime, DAY) AS los_hospital
    FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
    INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
        ON a.subject_id = p.subject_id
    WHERE p.gender = 'F'
        AND p.anchor_age BETWEEN 67 AND 77
),

-- Aggregate target cohort metrics
target_metrics AS (
    SELECT
        COUNT(*) AS n_target,
        AVG(t.mortality_30d) AS mortality_30d_rate,
        -- Cardiac complication rate
        COUNT(DISTINCT CASE WHEN cc.hadm_id IS NOT NULL THEN t.hadm_id END) * 1.0 / COUNT(DISTINCT t.hadm_id) AS cardiac_complication_rate,
        -- Neuro complication rate
        COUNT(DISTINCT CASE WHEN nc.hadm_id IS NOT NULL THEN t.hadm_id END) * 1.0 / COUNT(DISTINCT t.hadm_id) AS neuro_complication_rate,
        -- Mean LOS for survivors
        AVG(CASE WHEN t.hospital_expire_flag = 0 THEN t.los_hospital END) AS mean_los_survivors
    FROM target_cohort t
    LEFT JOIN cardiac_complications cc
        ON t.hadm_id = cc.hadm_id
    LEFT JOIN neuro_complications nc
        ON t.hadm_id = nc.hadm_id
),

-- Aggregate control cohort metrics
control_metrics AS (
    SELECT
        COUNT(*) AS n_control,
        -- Cardiac complication rate
        COUNT(DISTINCT CASE WHEN cc.hadm_id IS NOT NULL THEN c.hadm_id END) * 1.0 / COUNT(DISTINCT c.hadm_id) AS cardiac_complication_rate,
        -- Neuro complication rate
        COUNT(DISTINCT CASE WHEN nc.hadm_id IS NOT NULL THEN c.hadm_id END) * 1.0 / COUNT(DISTINCT c.hadm_id) AS neuro_complication_rate,
        -- Mean LOS for survivors
        AVG(CASE WHEN c.hospital_expire_flag = 0 THEN c.los_hospital END) AS mean_los_survivors,
        -- Collect LOS distribution for percentile calculation
        APPROX_QUANTILES(CASE WHEN c.hospital_expire_flag = 0 THEN c.los_hospital END, 100) AS los_quantiles
    FROM control_cohort c
    LEFT JOIN cardiac_complications cc
        ON c.hadm_id = cc.hadm_id
    LEFT JOIN neuro_complications nc
        ON c.hadm_id = nc.hadm_id
),

-- Calculate percentile of target mean LOS in control distribution
percentile_calc AS (
    SELECT
        (SELECT MAX(offset) / 100.0
         FROM UNNEST((SELECT los_quantiles FROM control_metrics)) AS q WITH OFFSET 
         WHERE q <= (SELECT mean_los_survivors FROM target_metrics)) AS percentile
)

-- Final output
SELECT
    -- Target cohort metrics
    n_target,
    mortality_30d_rate,
    target_metrics.cardiac_complication_rate AS target_cardiac_rate,
    target_metrics.neuro_complication_rate AS target_neuro_rate,
    target_metrics.mean_los_survivors AS target_mean_los,

    -- Control cohort metrics
    n_control,
    control_metrics.cardiac_complication_rate AS control_cardiac_rate,
    control_metrics.neuro_complication_rate AS control_neuro_rate,
    control_metrics.mean_los_survivors AS control_mean_los,

    -- Percentile
    percentile
FROM target_metrics
CROSS JOIN control_metrics
CROSS JOIN percentile_calc;