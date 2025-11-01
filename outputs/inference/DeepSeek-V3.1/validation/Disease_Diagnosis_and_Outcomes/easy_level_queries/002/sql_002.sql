WITH aki_admissions AS (
    SELECT 
        adm.subject_id,
        adm.hadm_id,
        DATE_DIFF(adm.dischtime, adm.admittime, DAY) AS los_days
    FROM `physionet-data.mimiciv_3_1_hosp.admissions` adm
    INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` pat
        ON adm.subject_id = pat.subject_id
    INNER JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` diag
        ON adm.hadm_id = diag.hadm_id AND adm.subject_id = diag.subject_id
    WHERE 
        pat.gender = 'M'
        AND pat.anchor_age BETWEEN 52 AND 62
        AND diag.seq_num = 1  -- primary diagnosis
        AND (
            (diag.icd_version = 10 AND diag.icd_code LIKE 'N17%') 
            OR (diag.icd_version = 9 AND diag.icd_code LIKE '584%')
        )
        AND adm.dischtime IS NOT NULL  -- ensure LOS can be computed
)
SELECT 
    APPROX_QUANTILES(los_days, 100)[OFFSET(75)] AS los_75th_percentile
FROM aki_admissions;