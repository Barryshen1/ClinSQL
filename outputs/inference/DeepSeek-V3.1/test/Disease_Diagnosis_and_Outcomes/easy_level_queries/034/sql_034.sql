WITH target_admissions AS (
    SELECT 
        adm.subject_id,
        adm.hadm_id,
        adm.admittime,
        adm.dischtime,
        DATE_DIFF(adm.dischtime, adm.admittime, DAY) AS los_days
    FROM `physionet-data.mimiciv_3_1_hosp.patients` pt
    INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` adm
        ON pt.subject_id = adm.subject_id
    INNER JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` dx
        ON adm.hadm_id = dx.hadm_id
    WHERE 
        pt.gender = 'F'
        AND pt.anchor_age BETWEEN 40 AND 50
        AND dx.seq_num = 1  -- primary diagnosis
        AND dx.icd_version = 10
        AND (
            dx.icd_code LIKE 'A41%'  -- sepsis
            OR dx.icd_code IN ('R65.20', 'R65.21')  -- septic shock
        )
        AND adm.dischtime IS NOT NULL  -- exclude ongoing admissions
)
SELECT 
    APPROX_QUANTILES(los_days, 100)[OFFSET(25)] AS q1,
    APPROX_QUANTILES(los_days, 100)[OFFSET(75)] AS q3
FROM target_admissions;