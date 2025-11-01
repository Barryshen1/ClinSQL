WITH 
aki_cohort AS (
    SELECT 
        p.subject_id, 
        a.hadm_id, 
        a.admittime, 
        a.dischtime, 
        a.deathtime,
        a.hospital_expire_flag,
        -- Check if death within 30 days of admission
        CASE WHEN a.deathtime IS NOT NULL AND 
                  DATETIME_DIFF(a.deathtime, a.admittime, DAY) <= 30 
             THEN 1 ELSE 0 END AS mortality_30day,
        -- Check for ARDS diagnosis during the admission
        MAX(CASE WHEN d.icd_code IN ('518.82', 'J80') THEN 1 ELSE 0 END) AS has_ards
    FROM `physionet-data.mimiciv_3_1_hosp.patients` p
    INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a
        ON p.subject_id = a.subject_id
    INNER JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
        ON a.hadm_id = d.hadm_id
    WHERE p.gender = 'M'
        AND p.anchor_age BETWEEN 74 AND 84
        AND d.icd_code IN ('584.9', 'N17.9')  -- AKI codes
    GROUP BY p.subject_id, a.hadm_id, a.admittime, a.dischtime, a.deathtime, a.hospital_expire_flag
),
general_cohort AS (
    SELECT 
        p.subject_id, 
        a.hadm_id, 
        a.admittime, 
        a.dischtime, 
        a.deathtime,
        a.hospital_expire_flag,
        -- Check for ARDS diagnosis during the admission
        MAX(CASE WHEN d.icd_code IN ('518.82', 'J80') THEN 1 ELSE 0 END) AS has_ards
    FROM `physionet-data.mimiciv_3_1_hosp.patients` p
    INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a
        ON p.subject_id = a.subject_id
    LEFT JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
        ON a.hadm_id = d.hadm_id
    WHERE p.gender = 'M'
        AND p.anchor_age BETWEEN 74 AND 84
    GROUP BY p.subject_id, a.hadm_id, a.admittime, a.dischtime, a.deathtime, a.hospital_expire_flag
),
aki_summary AS (
    SELECT 
        'AKI Cohort' AS cohort,
        COUNT(*) AS num_patients,
        NULL AS median_risk_score,  -- Cannot compute with available data
        NULL AS iqr_risk_score,     -- Cannot compute with available data
        AVG(1.0 * mortality_30day) * 100 AS mortality_30day_percent,
        AVG(1.0 * has_ards) * 100 AS ards_rate,
        (SELECT APPROX_QUANTILES(DATETIME_DIFF(dischtime, admittime, DAY), 100)[OFFSET(50)]
         FROM aki_cohort 
         WHERE hospital_expire_flag = 0) AS median_survivor_los
    FROM aki_cohort
),
general_summary AS (
    SELECT 
        'General Cohort' AS cohort,
        COUNT(*) AS num_patients,
        AVG(1.0 * has_ards) * 100 AS ards_rate,
        (SELECT APPROX_QUANTILES(DATETIME_DIFF(dischtime, admittime, DAY), 100)[OFFSET(50)]
         FROM general_cohort 
         WHERE hospital_expire_flag = 0) AS median_survivor_los
    FROM general_cohort
)
SELECT 
    a.cohort,
    a.num_patients,
    a.median_risk_score,
    a.iqr_risk_score,
    a.mortality_30day_percent,
    a.ards_rate AS ards_rate_aki,
    g.ards_rate AS ards_rate_general,
    a.median_survivor_los AS los_survivor_aki,
    g.median_survivor_los AS los_survivor_general
FROM aki_summary a
CROSS JOIN general_summary g;