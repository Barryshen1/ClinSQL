WITH first_troponin AS (
    SELECT 
        lab.hadm_id,
        MIN(lab.valuenum) AS first_troponin_value
    FROM `physionet-data.mimiciv_3_1_hosp.patients` pat
    INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` adm 
        ON pat.subject_id = adm.subject_id
    INNER JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` diag 
        ON adm.hadm_id = diag.hadm_id
    INNER JOIN `physionet-data.mimiciv_3_1_hosp.labevents` lab 
        ON adm.hadm_id = lab.hadm_id
    WHERE 
        pat.anchor_age = 52
        AND pat.gender = 'M'
        AND diag.icd_code LIKE 'I2[0-5]%'
        AND diag.icd_version = 10
        AND lab.itemid = 51003  -- Troponin-T
        AND lab.valuenum > 0.014
    GROUP BY lab.hadm_id
)
SELECT 
    PERCENTILE_CONT(first_troponin_value, 0.5) OVER() AS median_troponin,
    PERCENTILE_CONT(first_troponin_value, 0.25) OVER() AS q1_troponin,
    PERCENTILE_CONT(first_troponin_value, 0.75) OVER() AS q3_troponin
FROM first_troponin
LIMIT 1;