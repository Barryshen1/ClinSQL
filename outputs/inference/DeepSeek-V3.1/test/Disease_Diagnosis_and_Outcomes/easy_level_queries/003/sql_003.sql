WITH filtered_admissions AS (
    SELECT 
        adm.subject_id,
        adm.hadm_id,
        DATETIME_DIFF(adm.dischtime, adm.admittime, DAY) AS los_days
    FROM `physionet-data.mimiciv_3_1_hosp.patients` p
    INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` adm
        ON p.subject_id = adm.subject_id
    INNER JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` diag
        ON adm.subject_id = diag.subject_id AND adm.hadm_id = diag.hadm_id
    WHERE 
        p.gender = 'F'
        AND p.anchor_age BETWEEN 40 AND 50
        AND diag.seq_num = 1  -- primary diagnosis
        AND diag.icd_code LIKE 'I2[0-5]%'  -- ICD-10 codes I20 to I25 for ischemic heart disease
        AND diag.icd_version = 10
        AND adm.dischtime IS NOT NULL  -- exclude ongoing admissions
)
SELECT 
    PERCENTILE_CONT(los_days, 0.25) OVER() AS los_25th_percentile
FROM filtered_admissions
LIMIT 1;