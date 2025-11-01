WITH cohort AS (
    SELECT 
        adm.subject_id, 
        adm.hadm_id, 
        adm.admittime, 
        adm.dischtime, 
        adm.deathtime,
        adm.hospital_expire_flag,
        -- Check for AKI during the admission
        EXISTS (
            SELECT 1 
            FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` AS diag_aki
            WHERE diag_aki.subject_id = adm.subject_id 
                AND diag_aki.hadm_id = adm.hadm_id 
                AND diag_aki.icd_code LIKE 'N17%' 
                AND diag_aki.icd_version = 10
        ) AS aki,
        -- Check for ARDS during the admission
        EXISTS (
            SELECT 1 
            FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` AS diag_ards
            WHERE diag_ards.subject_id = adm.subject_id 
                AND diag_ards.hadm_id = adm.hadm_id 
                AND diag_ards.icd_code = 'J80' 
                AND diag_ards.icd_version = 10
        ) AS ards,
        -- 30-day mortality: died in hospital and within 30 days of admission
        CASE 
            WHEN adm.hospital_expire_flag = 1 
                AND DATETIME_DIFF(adm.deathtime, adm.admittime, DAY) <= 30 THEN 1
            ELSE 0
        END AS mortality_30day,
        -- Survival time in days for decedents
        CASE 
            WHEN adm.hospital_expire_flag = 1 THEN DATETIME_DIFF(adm.deathtime, adm.admittime, DAY)
            ELSE NULL
        END AS survival_days
    FROM `physionet-data.mimiciv_3_1_hosp.admissions` adm
    INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` pat
        ON adm.subject_id = pat.subject_id
    -- Ensure ICH diagnosis
    WHERE EXISTS (
        SELECT 1 
        FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` diag_ich
        WHERE diag_ich.subject_id = adm.subject_id 
            AND diag_ich.hadm_id = adm.hadm_id 
            AND diag_ich.icd_code IN ('I60', 'I61', 'I62') 
            AND diag_ich.icd_version = 10
    )
    -- Age and gender
    AND pat.anchor_age BETWEEN 68 AND 78
    AND pat.gender = 'M'
    -- Ensure ICU stay
    AND EXISTS (
        SELECT 1 
        FROM `physionet-data.mimiciv_3_1_icu.icustays` icu
        WHERE icu.subject_id = adm.subject_id 
            AND icu.hadm_id = adm.hadm_id
    )
)

SELECT 
    COUNT(*) AS cohort_size,
    SUM(mortality_30day) AS mortality_30day_count,
    AVG(CAST(mortality_30day AS FLOAT64)) * 100 AS mortality_30day_rate,
    SUM(CAST(aki AS INT64)) AS aki_count,
    AVG(CAST(aki AS INT64) * 100.0) AS aki_rate,
    SUM(CAST(ards AS INT64)) AS ards_count,
    AVG(CAST(ards AS INT64) * 100.0) AS ards_rate,
    -- Median survival among decedents (only non-null values)
    APPROX_QUANTILES(survival_days, 100) [SAFE_ORDINAL(50)] AS median_survival_days_decedents
FROM cohort;