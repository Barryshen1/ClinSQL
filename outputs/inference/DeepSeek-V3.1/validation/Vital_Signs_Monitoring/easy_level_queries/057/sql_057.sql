WITH cohort_stays AS (
    SELECT 
        ie.stay_id
    FROM `physionet-data.mimiciv_3_1_icu.icustays` ie
    INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
        ON ie.subject_id = p.subject_id
    WHERE 
        p.gender = 'M'
        AND p.anchor_age BETWEEN 35 AND 45
),
max_rr_per_stay AS (
    SELECT 
        ce.stay_id,
        MAX(ce.valuenum) AS max_rr
    FROM `physionet-data.mimiciv_3_1_icu.chartevents` ce
    INNER JOIN cohort_stays cs
        ON ce.stay_id = cs.stay_id
    INNER JOIN `physionet-data.mimiciv_3_1_icu.d_items` di
        ON ce.itemid = di.itemid
    WHERE 
        di.itemid IN (220210, 224690)  -- Respiratory Rate
        AND ce.valuenum IS NOT NULL
        AND ce.valuenum > 0
        AND ce.valuenum < 100  -- reasonable range
    GROUP BY ce.stay_id
)
SELECT 
    MIN(max_rr) AS min_of_max_rr
FROM max_rr_per_stay;