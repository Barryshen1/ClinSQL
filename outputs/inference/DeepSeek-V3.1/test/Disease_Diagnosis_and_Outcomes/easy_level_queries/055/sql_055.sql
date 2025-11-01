WITH aki_admissions AS (
    SELECT 
        adm.subject_id,
        adm.hadm_id,
        adm.admittime,
        adm.dischtime,
        DATETIME_DIFF(adm.dischtime, adm.admittime, DAY) AS los_days,
        pat.anchor_age
    FROM `physionet-data.mimiciv_3_1_hosp.admissions` adm
    INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` pat
        ON adm.subject_id = pat.subject_id
    INNER JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` diag
        ON adm.hadm_id = diag.hadm_id
    WHERE 
        pat.gender = 'M'
        AND pat.anchor_age BETWEEN 37 AND 47
        AND diag.seq_num = 1  -- primary diagnosis
        AND (
            -- ICD-9 codes for AKI
            (diag.icd_version = 9 AND diag.icd_code IN ('584.5', '584.6', '584.7', '584.8', '584.9'))
            OR
            -- ICD-10 codes for AKI
            (diag.icd_version = 10 AND diag.icd_code IN ('N17.0', 'N17.1', 'N17.2', 'N17.8', 'N17.9'))
        )
        AND adm.dischtime > adm.admittime  -- valid LOS
)
SELECT 
    APPROX_QUANTILES(los_days, 100)[OFFSET(75)] AS los_75th_percentile_days
FROM aki_admissions;