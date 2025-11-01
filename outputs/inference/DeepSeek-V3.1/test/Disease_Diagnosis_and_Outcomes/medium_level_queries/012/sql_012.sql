WITH cohort AS (
    SELECT 
        p.subject_id, 
        p.gender, 
        p.anchor_age,
        a.hadm_id,
        a.admittime,
        a.dischtime,
        a.hospital_expire_flag,
        -- Calculate LOS in days
        DATETIME_DIFF(a.dischtime, a.admittime, DAY) AS los_days,
        -- ICU flag: if hadm_id exists in icustays
        CASE WHEN i.stay_id IS NOT NULL THEN 'ICU' ELSE 'non-ICU' END AS icu_stratum,
        -- LOS group
        CASE WHEN DATETIME_DIFF(a.dischtime, a.admittime, DAY) < 8 THEN '<8' ELSE '>=8' END AS los_stratum
    FROM `physionet-data.mimiciv_3_1_hosp.patients` p
    INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a
        ON p.subject_id = a.subject_id
    LEFT JOIN `physionet-data.mimiciv_3_1_icu.icustays` i
        ON a.hadm_id = i.hadm_id
    WHERE p.gender = 'F'
        AND p.anchor_age BETWEEN 83 AND 93
        AND a.hadm_id IN (
            SELECT hadm_id 
            FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` 
            WHERE 
                (icd_version = 10 AND icd_code LIKE 'I50%') OR 
                (icd_version = 9 AND icd_code LIKE '428%')
        )
),

-- Comorbidities: we define flags for 6 chronic conditions
comorbidities AS (
    SELECT 
        hadm_id,
        MAX(CASE WHEN 
            (icd_version = 10 AND (icd_code LIKE 'N18%' OR icd_code LIKE 'I13%')) OR
            (icd_version = 9 AND (icd_code LIKE '585%' OR icd_code LIKE '586%'))
            THEN 1 ELSE 0 END) AS ckd,
        MAX(CASE WHEN 
            (icd_version = 10 AND icd_code LIKE 'E1%') OR
            (icd_version = 9 AND icd_code LIKE '250%')
            THEN 1 ELSE 0 END) AS diabetes,
        MAX(CASE WHEN 
            (icd_version = 10 AND icd_code LIKE 'I10%') OR
            (icd_version = 9 AND icd_code LIKE '401%')
            THEN 1 ELSE 0 END) AS hypertension,
        MAX(CASE WHEN 
            (icd_version = 10 AND (icd_code LIKE 'J4%' OR icd_code LIKE 'J44%')) OR
            (icd_version = 9 AND (icd_code LIKE '491%' OR icd_code LIKE '492%' OR icd_code LIKE '496%'))
            THEN 1 ELSE 0 END) AS copd,
        MAX(CASE WHEN 
            (icd_version = 10 AND (icd_code LIKE 'K70%' OR icd_code LIKE 'K71%' OR icd_code LIKE 'K74%')) OR
            (icd_version = 9 AND (icd_code LIKE '570%' OR icd_code LIKE '571%'))
            THEN 1 ELSE 0 END) AS liver,
        MAX(CASE WHEN 
            (icd_version = 10 AND icd_code LIKE 'C%') OR
            (icd_version = 9 AND icd_code LIKE '1%' OR icd_code LIKE '2%' OR icd_code LIKE '14%' OR icd_code LIKE '15%' OR icd_code LIKE '16%' OR icd_code LIKE '17%' OR icd_code LIKE '18%' OR icd_code LIKE '19%' OR icd_code LIKE '20%')
            THEN 1 ELSE 0 END) AS cancer
    FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd`
    GROUP BY hadm_id
),

comorbidity_burden AS (
    SELECT
        hadm_id,
        ckd,
        diabetes,
        (ckd + diabetes + hypertension + copd + liver + cancer) AS comorbidity_count,
        CASE 
            WHEN (ckd + diabetes + hypertension + copd + liver + cancer) <= 1 THEN '0-1'
            WHEN (ckd + diabetes + hypertension + copd + liver + cancer) = 2 THEN '2'
            ELSE '>=3'
        END AS comorbidity_stratum
    FROM comorbidities
)

SELECT
    c.icu_stratum,
    c.los_stratum,
    cb.comorbidity_stratum,
    COUNT(*) AS n_patients,
    -- Mortality %
    ROUND(100.0 * SUM(c.hospital_expire_flag) / COUNT(*), 2) AS mortality_percent,
    -- Median LOS
    APPROX_QUANTILES(c.los_days, 100)[OFFSET(50)] AS median_los,
    -- CKD prevalence
    ROUND(100.0 * SUM(cb.ckd) / COUNT(*), 2) AS ckd_percent,
    -- Diabetes prevalence
    ROUND(100.0 * SUM(cb.diabetes) / COUNT(*), 2) AS diabetes_percent
FROM cohort c
INNER JOIN comorbidity_burden cb
    ON c.hadm_id = cb.hadm_id
GROUP BY c.icu_stratum, c.los_stratum, cb.comorbidity_stratum
ORDER BY c.icu_stratum, c.los_stratum, cb.comorbidity_stratum;