WITH icu_stays AS (
    SELECT 
        i.subject_id, 
        i.hadm_id, 
        i.stay_id, 
        i.intime, 
        i.outtime
    FROM `physionet-data.mimiciv_3_1_icu.icustays` i
    INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` p 
        ON i.subject_id = p.subject_id
    WHERE p.gender = 'M'
),
chart_pH AS (
    SELECT 
        ce.stay_id, 
        ce.valuenum AS pH
    FROM `physionet-data.mimiciv_3_1_icu.chartevents` ce
    INNER JOIN icu_stays s 
        ON ce.stay_id = s.stay_id
    WHERE 
        ce.itemid = 223830  -- Arterial pH in chartevents
        AND ce.valuenum BETWEEN 6.5 AND 8.0
        AND ce.charttime BETWEEN s.intime AND s.outtime
),
lab_pH AS (
    SELECT 
        s.stay_id, 
        le.valuenum AS pH
    FROM `physionet-data.mimiciv_3_1_hosp.labevents` le
    INNER JOIN icu_stays s 
        ON le.subject_id = s.subject_id 
        AND le.hadm_id = s.hadm_id
    WHERE 
        le.itemid = 50820  -- Arterial pH in labevents
        AND le.valuenum BETWEEN 6.5 AND 8.0
        AND le.charttime BETWEEN s.intime AND s.outtime
),
all_pH AS (
    SELECT stay_id, pH FROM chart_pH
    UNION ALL
    SELECT stay_id, pH FROM lab_pH
),
peak_pH_per_stay AS (
    SELECT 
        stay_id, 
        MAX(pH) AS peak_pH
    FROM all_pH
    GROUP BY stay_id
),
quantiles AS (
    SELECT 
        APPROX_QUANTILES(peak_pH, 4) AS q
    FROM peak_pH_per_stay
)
SELECT 
    q[OFFSET(1)] AS q1,  -- 25th percentile
    q[OFFSET(3)] AS q3,  -- 75th percentile
    q[OFFSET(3)] - q[OFFSET(1)] AS iqr
FROM quantiles;