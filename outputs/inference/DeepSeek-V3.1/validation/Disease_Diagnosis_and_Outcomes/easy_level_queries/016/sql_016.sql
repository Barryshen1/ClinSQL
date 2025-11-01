WITH pneumonia_admissions AS (
    SELECT DISTINCT diag.hadm_id
    FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` diag
    INNER JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` d
        ON diag.icd_code = d.icd_code AND diag.icd_version = d.icd_version
    WHERE d.icd_code LIKE 'J18%'  -- Pneumonia
),
copd_admissions AS (
    SELECT DISTINCT diag.hadm_id
    FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` diag
    INNER JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` d
        ON diag.icd_code = d.icd_code AND diag.icd_version = d.icd_version
    WHERE d.icd_code LIKE 'J44%'  -- COPD
),
target_admissions AS (
    SELECT p.hadm_id
    FROM pneumonia_admissions p
    INNER JOIN copd_admissions c
        ON p.hadm_id = c.hadm_id
),
target_patients AS (
    SELECT a.hadm_id, 
        DATE_DIFF(a.dischtime, a.admittime, DAY) AS los
    FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
    INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
        ON a.subject_id = p.subject_id
    INNER JOIN target_admissions ta
        ON a.hadm_id = ta.hadm_id
    WHERE p.gender = 'M'
        AND p.anchor_age BETWEEN 68 AND 78
        AND a.dischtime IS NOT NULL  -- Exclude ongoing admissions
)
SELECT 
    PERCENTILE_CONT(los, 0.75) OVER() AS los_75th_percentile
FROM target_patients
LIMIT 1;