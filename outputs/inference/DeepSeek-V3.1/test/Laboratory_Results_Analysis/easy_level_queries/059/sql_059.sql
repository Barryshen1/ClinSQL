WITH sepsis_admissions AS (
    SELECT DISTINCT adm.subject_id, adm.hadm_id, adm.dischtime
    FROM `physionet-data.mimiciv_3_1_hosp.admissions` adm
    INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` pat
        ON adm.subject_id = pat.subject_id
    INNER JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` diag
        ON adm.hadm_id = diag.hadm_id
    WHERE pat.gender = 'M'
        AND pat.anchor_age = 93
        AND (
            (diag.icd_version = 9 AND diag.icd_code LIKE '038%') OR
            (diag.icd_version = 10 AND (diag.icd_code LIKE 'A41%' OR diag.icd_code LIKE 'R65%'))
        )
),
platelet_discharge AS (
    SELECT lab.valuenum
    FROM `physionet-data.mimiciv_3_1_hosp.labevents` lab
    INNER JOIN sepsis_admissions adm
        ON lab.hadm_id = adm.hadm_id
    WHERE lab.itemid = 51265  -- Platelet Count
        AND DATE(lab.charttime) = DATE(adm.dischtime)
        AND lab.valuenum IS NOT NULL
)
SELECT DISTINCT
    PERCENTILE_CONT(valuenum, 0.75) OVER() AS percentile_75_platelet_count
FROM platelet_discharge;