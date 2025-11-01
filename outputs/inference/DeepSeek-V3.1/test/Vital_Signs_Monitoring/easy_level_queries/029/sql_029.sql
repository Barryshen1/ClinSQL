WITH first_spo2 AS (
    SELECT 
        ce.subject_id,
        ce.valuenum AS spo2
    FROM `physionet-data.mimiciv_3_1_icu.chartevents` ce
    INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` p 
        ON ce.subject_id = p.subject_id
    WHERE ce.itemid = 220277  -- SpO2
        AND ce.valuenum IS NOT NULL
        AND p.gender = 'M'
        AND p.anchor_age BETWEEN 62 AND 72
    QUALIFY ROW_NUMBER() OVER (
        PARTITION BY ce.subject_id 
        ORDER BY ce.charttime
    ) = 1
)
SELECT 
    APPROX_QUANTILES(spo2, 4)[OFFSET(1)] AS q1,
    APPROX_QUANTILES(spo2, 4)[OFFSET(3)] AS q3,
    APPROX_QUANTILES(spo2, 4)[OFFSET(3)] - APPROX_QUANTILES(spo2, 4)[OFFSET(1)] AS iqr
FROM first_spo2;