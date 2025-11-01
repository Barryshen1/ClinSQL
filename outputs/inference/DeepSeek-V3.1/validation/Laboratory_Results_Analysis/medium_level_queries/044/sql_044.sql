WITH admissions_filtered AS (
    -- Get admissions for male patients aged 54-64
    SELECT adm.hadm_id
    FROM `physionet-data.mimiciv_3_1_hosp.admissions` adm
    INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` pat
        ON adm.subject_id = pat.subject_id
    WHERE pat.gender = 'M'
        AND pat.anchor_age BETWEEN 54 AND 64
), initial_troponin AS (
    -- For each qualifying admission, get the first troponin-T >0.01
    SELECT 
        le.hadm_id,
        MIN(le.charttime) AS first_charttime
    FROM `physionet-data.mimiciv_3_1_hosp.labevents` le
    INNER JOIN admissions_filtered af
        ON le.hadm_id = af.hadm_id
    WHERE le.itemid = 51003  -- Troponin-T
        AND le.valuenum > 0.01
    GROUP BY le.hadm_id
), troponin_values AS (
    -- Retrieve the actual value for that first event
    SELECT le.valuenum
    FROM `physionet-data.mimiciv_3_1_hosp.labevents` le
    INNER JOIN initial_troponin it
        ON le.hadm_id = it.hadm_id 
        AND le.charttime = it.first_charttime
    WHERE le.itemid = 51003
)
SELECT
    COUNT(valuenum) AS n,
    AVG(valuenum) AS mean,
    STDDEV(valuenum) AS sd,
    MIN(valuenum) AS min_value,
    MAX(valuenum) AS max_value,
    APPROX_QUANTILES(valuenum, 100)[OFFSET(25)] AS p25,
    APPROX_QUANTILES(valuenum, 100)[OFFSET(50)] AS median,
    APPROX_QUANTILES(valuenum, 100)[OFFSET(75)] AS p75
FROM troponin_values;