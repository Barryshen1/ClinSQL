WITH eligible_patients AS (
    SELECT subject_id
    FROM `physionet-data.mimiciv_3_1_hosp.patients`
    WHERE gender = 'F'
    AND anchor_age BETWEEN 82 AND 92
),
max_map_per_admission AS (
    SELECT 
        ie.hadm_id,
        MAX(ce.valuenum) AS max_map
    FROM `physionet-data.mimiciv_3_1_icu.chartevents` ce
    INNER JOIN `physionet-data.mimiciv_3_1_icu.icustays` ie
        ON ce.stay_id = ie.stay_id
    INNER JOIN eligible_patients p
        ON ie.subject_id = p.subject_id
    WHERE ce.itemid = 220181  -- MAP measurement
    AND ce.valuenum IS NOT NULL
    GROUP BY ie.hadm_id
)
SELECT 
    PERCENTILE_CONT(max_map, 0.5) OVER() AS median_max_map
FROM max_map_per_admission
LIMIT 1;