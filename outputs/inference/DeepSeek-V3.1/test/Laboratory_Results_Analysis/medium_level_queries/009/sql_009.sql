WITH first_troponin AS (
    SELECT 
        p.subject_id,
        a.hadm_id,
        p.anchor_age,
        l.charttime,
        l.valuenum AS first_troponin_value
    FROM `physionet-data.mimiciv_3_1_hosp.patients` p
    INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a
        ON p.subject_id = a.subject_id
    INNER JOIN `physionet-data.mimiciv_3_1_hosp.labevents` l
        ON a.hadm_id = l.hadm_id
    WHERE 
        p.gender = 'F'
        AND p.anchor_age BETWEEN 59 AND 69
        AND l.itemid = 51003  -- hs-TnT
        AND l.valuenum > 0.014
        AND l.valuenum IS NOT NULL
        AND l.valueuom = 'ng/mL'  -- ensure consistent unit
    QUALIFY ROW_NUMBER() OVER (PARTITION BY a.hadm_id ORDER BY l.charttime) = 1
)
SELECT
    MIN(first_troponin_value) AS min_value,
    MAX(first_troponin_value) AS max_value,
    APPROX_QUANTILES(first_troponin_value, 4)[OFFSET(1)] AS percentile_25,
    APPROX_QUANTILES(first_troponin_value, 2)[OFFSET(1)] AS median,
    APPROX_QUANTILES(first_troponin_value, 4)[OFFSET(3)] AS percentile_75
FROM first_troponin;