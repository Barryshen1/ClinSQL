WITH first_rr AS (
    SELECT 
        ce.valuenum AS respiratory_rate
    FROM 
        `physionet-data.mimiciv_3_1_icu.chartevents` ce
    INNER JOIN 
        `physionet-data.mimiciv_3_1_icu.icustays` ie 
        ON ce.stay_id = ie.stay_id
    INNER JOIN 
        `physionet-data.mimiciv_3_1_hosp.admissions` adm 
        ON ie.hadm_id = adm.hadm_id
    INNER JOIN 
        `physionet-data.mimiciv_3_1_hosp.patients` pat 
        ON adm.subject_id = pat.subject_id
    WHERE 
        pat.gender = 'F' 
        AND pat.anchor_age BETWEEN 73 AND 83
        AND ce.itemid = 220210  -- Respiratory Rate
        AND ce.valuenum IS NOT NULL
    QUALIFY 
        ROW_NUMBER() OVER (PARTITION BY adm.hadm_id ORDER BY ce.charttime) = 1
)
SELECT 
    STDDEV(respiratory_rate) AS sd_first_respiratory_rate
FROM 
    first_rr;