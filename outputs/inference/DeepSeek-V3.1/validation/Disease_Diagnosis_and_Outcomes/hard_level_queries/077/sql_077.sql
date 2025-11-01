WITH cohort AS (
    SELECT 
        p.subject_id,
        p.anchor_age,
        a.hadm_id,
        a.hospital_expire_flag,
        a.deathtime,
        a.admittime,
        -- Check for AKI during the admission
        MAX(CASE WHEN d.icd_code LIKE 'N17%' THEN 1 ELSE 0 END) AS aki,
        -- Check for ARDS during the admission
        MAX(CASE WHEN d.icd_code LIKE 'J80%' THEN 1 ELSE 0 END) AS ards
    FROM `physionet-data.mimiciv_3_1_hosp.patients` p
    INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a
        ON p.subject_id = a.subject_id
    INNER JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` diag
        ON a.hadm_id = diag.hadm_id
    INNER JOIN `physionet-data.mimiciv_3_1_icu.icustays` icu
        ON a.hadm_id = icu.hadm_id
    LEFT JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
        ON a.hadm_id = d.hadm_id
    WHERE 
        p.anchor_age BETWEEN 88 AND 98
        AND p.gender = 'M'
        AND diag.icd_code LIKE 'J18%'  -- Pneumonia
        AND diag.seq_num = 1  -- Primary diagnosis
    GROUP BY p.subject_id, p.anchor_age, a.hadm_id, a.hospital_expire_flag, a.deathtime, a.admittime
),
decedent_survival AS (
    SELECT 
        subject_id,
        hadm_id,
        DATE_DIFF(deathtime, admittime, DAY) AS survival_days
    FROM cohort
    WHERE hospital_expire_flag = 1
)
SELECT
    COUNT(*) AS cohort_size,
    -- Composite risk score not available; returning NULL
    NULL AS min_score,
    NULL AS p25_score,
    NULL AS median_score,
    NULL AS p75_score,
    NULL AS max_score,
    -- Outcomes
    ROUND(100.0 * SUM(hospital_expire_flag) / COUNT(*), 2) AS mortality_rate_percent,
    ROUND(100.0 * SUM(aki) / COUNT(*), 2) AS aki_rate_percent,
    ROUND(100.0 * SUM(ards) / COUNT(*), 2) AS ards_rate_percent,
    -- Median survival for decedents
    (SELECT PERCENTILE_CONT(survival_days, 0.5) OVER() FROM decedent_survival LIMIT 1) AS median_survival_days
FROM cohort;