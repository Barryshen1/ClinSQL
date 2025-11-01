WITH cohort AS (
    SELECT 
        p.subject_id,
        a.hadm_id,
        p.anchor_age,
        a.admittime,
        a.dischtime,
        p.dod,
        -- Check for 30-day mortality
        CASE WHEN DATE_DIFF(CAST(p.dod AS DATE), CAST(a.admittime AS DATE), DAY) <= 30 THEN 1 ELSE 0 END AS mortality_30day,
        -- Check for AKI (ICD9: 584, ICD10: N17)
        CASE WHEN EXISTS (
            SELECT 1 FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` di 
            WHERE di.subject_id = a.subject_id AND di.hadm_id = a.hadm_id 
            AND (di.icd_code LIKE '584%' OR di.icd_code LIKE 'N17%')
        ) THEN 1 ELSE 0 END AS aki,
        -- Check for ARDS (ICD9: 518.82, ICD10: J80)
        CASE WHEN EXISTS (
            SELECT 1 FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` di 
            WHERE di.subject_id = a.subject_id AND di.hadm_id = a.hadm_id 
            AND (di.icd_code = '518.82' OR di.icd_code = 'J80')
        ) THEN 1 ELSE 0 END AS ards
    FROM `physionet-data.mimiciv_3_1_hosp.patients` p
    INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a
        ON p.subject_id = a.subject_id
    -- Filter: female, age 88-98
    WHERE p.gender = 'F'
        AND p.anchor_age BETWEEN 88 AND 98
    -- Has AMI (ICD9: 410.x, ICD10: I21.x, I22.x)
    AND EXISTS (
        SELECT 1 FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` di
        WHERE di.subject_id = a.subject_id AND di.hadm_id = a.hadm_id
        AND (
            (di.icd_version = 9 AND di.icd_code LIKE '410%') OR
            (di.icd_version = 10 AND (di.icd_code LIKE 'I21%' OR di.icd_code LIKE 'I22%'))
        )
    )
    -- Has an ICU stay
    AND EXISTS (
        SELECT 1 FROM `physionet-data.mimiciv_3_1_icu.icustays` ie
        WHERE ie.subject_id = a.subject_id AND ie.hadm_id = a.hadm_id
    )
),
decedents AS (
    SELECT 
        subject_id,
        hadm_id,
        DATE_DIFF(CAST(dod AS DATE), CAST(admittime AS DATE), DAY) AS survival_days
    FROM cohort
    WHERE dod IS NOT NULL
)
SELECT 
    COUNT(*) AS total_patients,
    AVG(mortality_30day) * 100 AS mortality_30day_rate_percent,
    AVG(aki) * 100 AS aki_rate_percent,
    AVG(ards) * 100 AS ards_rate_percent,
    (SELECT PERCENTILE_CONT(survival_days, 0.5) OVER() FROM decedents LIMIT 1) AS median_survival_days_decedents
FROM cohort;