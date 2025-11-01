WITH stroke_cohort AS (
    SELECT 
        adm.subject_id,
        adm.hadm_id,
        DATE_DIFF(adm.dischtime, adm.admittime, DAY) AS los_hospital
    FROM `physionet-data.mimiciv_3_1_hosp.admissions` adm
    INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` pat
        ON adm.subject_id = pat.subject_id
    INNER JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` diag
        ON adm.hadm_id = diag.hadm_id
    WHERE 
        pat.gender = 'M'
        AND pat.anchor_age BETWEEN 45 AND 55
        AND diag.seq_num = 1
        AND (
            (diag.icd_version = 10 AND diag.icd_code LIKE 'I6%') -- I60, I61, I62
            OR (diag.icd_version = 9 AND diag.icd_code LIKE '43%') -- 430, 431, 432
        )
)
SELECT 
    STDDEV(los_hospital) AS sd_length_of_stay
FROM stroke_cohort;