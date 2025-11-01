WITH per_stay_mean_rr AS (
    SELECT 
        ie.stay_id,
        AVG(ce.valuenum) AS mean_resp_rate
    FROM `physionet-data.mimiciv_3_1_icu.chartevents` ce
    INNER JOIN `physionet-data.mimiciv_3_1_icu.icustays` ie
        ON ce.stay_id = ie.stay_id
    INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
        ON ie.subject_id = p.subject_id
    WHERE 
        p.gender = 'F'
        AND p.anchor_age BETWEEN 39 AND 49
        AND ce.itemid = 220210  -- Respiratory rate
        AND ce.valuenum IS NOT NULL
        AND ce.valuenum > 0  -- Exclude non-physiological values
    GROUP BY ie.stay_id
)
SELECT 
    APPROX_QUANTILES(mean_resp_rate, 100)[OFFSET(75)] AS percentile_75
FROM per_stay_mean_rr;