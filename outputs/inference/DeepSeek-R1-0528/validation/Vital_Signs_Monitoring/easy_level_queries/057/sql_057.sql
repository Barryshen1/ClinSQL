WITH eligible_stays AS (
    SELECT 
        ie.stay_id,
        ie.intime,
        ie.outtime
    FROM `physionet-data.mimiciv_3_1_icu.icustays` ie
    INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` pt
        ON ie.subject_id = pt.subject_id
    WHERE 
        pt.gender = 'M'
        AND pt.anchor_age + (EXTRACT(YEAR FROM ie.intime) - pt.anchor_year) BETWEEN 35 AND 45
),
max_rates_per_stay AS (
    SELECT 
        e.stay_id,
        MAX(ce.valuenum) AS max_resp_rate
    FROM eligible_stays e
    INNER JOIN `physionet-data.mimiciv_3_1_icu.chartevents` ce
        ON e.stay_id = ce.stay_id
    WHERE 
        ce.itemid IN (220210, 224688)  -- Respiratory Rate item IDs
        AND ce.valuenum IS NOT NULL    -- Ensure numeric value exists
        AND ce.charttime >= e.intime   -- Event during ICU stay
        AND ce.charttime <= e.outtime
    GROUP BY e.stay_id
)
SELECT 
    MIN(max_resp_rate) AS min_of_max_resp_rate
FROM max_rates_per_stay;