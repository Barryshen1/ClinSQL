WITH dialysis_admissions AS (
    SELECT DISTINCT
        adm.subject_id,
        adm.hadm_id,
        DATE_DIFF(adm.dischtime, adm.admittime, DAY) AS los_days
    FROM `physionet-data.mimiciv_3_1_hosp.admissions` adm
    INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` pat
        ON adm.subject_id = pat.subject_id
    INNER JOIN `physionet-data.mimiciv_3_1_hosp.procedures_icd` proc
        ON adm.hadm_id = proc.hadm_id
    WHERE 
        pat.gender = 'M'
        AND pat.anchor_age BETWEEN 44 AND 54
        AND proc.icd_version = 10
        AND proc.icd_code LIKE '5A1D%'
)
SELECT 
    STDDEV(los_days) AS sd_length_of_stay_days
FROM dialysis_admissions;