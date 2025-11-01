WITH sepsis_admissions AS (
    SELECT 
        adm.subject_id,
        adm.hadm_id,
        adm.admittime,
        adm.dischtime,
        DATE_DIFF(adm.dischtime, adm.admittime, DAY) AS los_days
    FROM `physionet-data.mimiciv_3_1_hosp.admissions` adm
    INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` pat
        ON adm.subject_id = pat.subject_id
    INNER JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` diag
        ON adm.hadm_id = diag.hadm_id
    INNER JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` d
        ON diag.icd_code = d.icd_code AND diag.icd_version = d.icd_version
    WHERE 
        pat.gender = 'F'
        AND pat.anchor_age BETWEEN 67 AND 77
        AND diag.seq_num = 1  -- primary diagnosis
        AND (
            d.icd_code LIKE 'A41%'  -- sepsis
            OR d.icd_code = 'R65.21'  -- septic shock
        )
        AND adm.dischtime IS NOT NULL  -- exclude ongoing admissions
)
SELECT 
    STDDEV(los_days) AS los_stddev_days
FROM sepsis_admissions;