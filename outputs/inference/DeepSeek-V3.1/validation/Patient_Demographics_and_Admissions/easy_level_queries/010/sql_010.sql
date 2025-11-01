WITH aki_patients AS (
    SELECT DISTINCT diag.hadm_id
    FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` diag
    WHERE 
        (diag.icd_version = 10 AND diag.icd_code LIKE 'N17%') OR 
        (diag.icd_version = 9 AND diag.icd_code LIKE '584%')
)
SELECT
    PERCENTILE_CONT(los, 0.25) OVER() AS los_25th_percentile
FROM `physionet-data.mimiciv_3_1_icu.icustays` icu
INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` pat
    ON icu.subject_id = pat.subject_id
INNER JOIN aki_patients aki
    ON icu.hadm_id = aki.hadm_id
WHERE 
    pat.gender = 'F'
    AND pat.anchor_age BETWEEN 48 AND 58
LIMIT 1;