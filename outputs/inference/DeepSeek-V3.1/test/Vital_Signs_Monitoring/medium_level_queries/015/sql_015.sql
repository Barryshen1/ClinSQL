WITH sbp_per_stay AS (
    SELECT 
        ie.stay_id,
        MAX(ce.valuenum) AS max_sbp
    FROM `physionet-data.mimiciv_3_1_icu.chartevents` ce
    INNER JOIN `physionet-data.mimiciv_3_1_icu.icustays` ie
        ON ce.stay_id = ie.stay_id
    INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` adm
        ON ie.hadm_id = adm.hadm_id
    INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` pat
        ON adm.subject_id = pat.subject_id
    WHERE 
        pat.gender = 'F'
        AND pat.anchor_age BETWEEN 59 AND 69
        AND adm.admission_type = 'EMERGENCY'
        AND ce.itemid = 220045   -- Systolic blood pressure
        AND ce.valuenum IS NOT NULL
    GROUP BY ie.stay_id
)
SELECT 
    PERCENTILE_CONT(max_sbp, 0.75) OVER() AS percentile_75
FROM sbp_per_stay
LIMIT 1;