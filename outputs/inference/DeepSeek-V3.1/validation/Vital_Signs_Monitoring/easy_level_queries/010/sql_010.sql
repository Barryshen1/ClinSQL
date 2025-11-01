WITH filtered_patients AS (
    SELECT subject_id
    FROM `physionet-data.mimiciv_3_1_hosp.patients`
    WHERE gender = 'F'
    AND anchor_age BETWEEN 71 AND 81
),
dbp_events AS (
    SELECT 
        ce.subject_id,
        ie.hadm_id,
        ce.valuenum AS dbp
    FROM `physionet-data.mimiciv_3_1_icu.chartevents` ce
    INNER JOIN `physionet-data.mimiciv_3_1_icu.icustays` ie
        ON ce.stay_id = ie.stay_id
    INNER JOIN filtered_patients fp
        ON ce.subject_id = fp.subject_id
    WHERE ce.itemid IN (220180, 225310, 8368, 8441)
    AND ce.valuenum IS NOT NULL
    AND ce.valuenum > 0  -- exclude negative or zero values
),
max_dbp_per_stay AS (
    SELECT 
        hadm_id,
        MAX(dbp) AS max_dbp
    FROM dbp_events
    GROUP BY hadm_id
)
SELECT 
    APPROX_QUANTILES(max_dbp, 100)[OFFSET(50)] AS median_max_dbp
FROM max_dbp_per_stay;