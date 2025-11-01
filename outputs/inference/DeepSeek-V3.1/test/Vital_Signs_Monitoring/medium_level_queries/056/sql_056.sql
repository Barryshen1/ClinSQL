WITH eligible_patients AS (
    SELECT p.subject_id, p.anchor_age
    FROM `physionet-data.mimiciv_3_1_hosp.patients` p
    WHERE p.gender = 'F'
    AND p.anchor_age BETWEEN 89 AND 99
),
icu_stays AS (
    SELECT ie.subject_id, ie.hadm_id, ie.stay_id
    FROM `physionet-data.mimiciv_3_1_icu.icustays` ie
    INNER JOIN eligible_patients ep ON ie.subject_id = ep.subject_id
),
temp_measurements AS (
    SELECT 
        ce.subject_id, 
        ce.hadm_id,
        ce.stay_id,
        ce.charttime,
        -- Convert to Celsius: if Fahrenheit (itemid=223761) then (valuenum-32)*5/9, else valuenum
        CASE 
            WHEN ce.itemid = 223761 THEN (ce.valuenum - 32) * 5.0/9.0
            ELSE ce.valuenum
        END AS temp_c,
        -- Categorize
        CASE 
            WHEN (CASE WHEN ce.itemid = 223761 THEN (ce.valuenum - 32) * 5.0/9.0 ELSE ce.valuenum END) < 36 THEN '<36'
            WHEN (CASE WHEN ce.itemid = 223761 THEN (ce.valuenum - 32) * 5.0/9.0 ELSE ce.valuenum END) BETWEEN 36 AND 37.9 THEN '36-37.9'
            WHEN (CASE WHEN ce.itemid = 223761 THEN (ce.valuenum - 32) * 5.0/9.0 ELSE ce.valuenum END) >= 38 THEN '>=38'
            ELSE NULL
        END AS category
    FROM `physionet-data.mimiciv_3_1_icu.chartevents` ce
    INNER JOIN icu_stays ie ON ce.stay_id = ie.stay_id
    WHERE ce.itemid IN (223762, 223761)  -- Temperature Celsius and Fahrenheit
    AND ce.valuenum IS NOT NULL
    AND ce.valuenum > 0  -- reasonable values
),
patient_mortality AS (
    SELECT 
        a.subject_id, 
        a.hadm_id,
        MAX(a.hospital_expire_flag) AS died  -- 1 if died in hospital
    FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
    INNER JOIN eligible_patients ep ON a.subject_id = ep.subject_id
    GROUP BY a.subject_id, a.hadm_id
),
category_aggregates AS (
    SELECT 
        category,
        COUNT(DISTINCT subject_id) AS n_patients,
        COUNT(*) AS n_measurements,
        AVG(temp_c) AS mean_temp,
        APPROX_QUANTILES(temp_c, 100) AS quantiles
    FROM temp_measurements
    WHERE category IS NOT NULL
    GROUP BY category
),
category_patients AS (
    SELECT 
        category,
        subject_id
    FROM temp_measurements
    WHERE category IS NOT NULL
    GROUP BY category, subject_id
),
mortality_rates AS (
    SELECT 
        cp.category,
        AVG(pm.died) AS mi_rate
    FROM category_patients cp
    INNER JOIN patient_mortality pm ON cp.subject_id = pm.subject_id
    GROUP BY cp.category
)
SELECT 
    ca.category,
    ca.n_patients,
    ca.n_measurements,
    ca.mean_temp,
    -- Extract median and IQR from quantiles array
    ca.quantiles[OFFSET(50)] AS median_temp,
    ca.quantiles[OFFSET(25)] AS q1_temp,
    ca.quantiles[OFFSET(75)] AS q3_temp,
    mr.mi_rate
FROM category_aggregates ca
INNER JOIN mortality_rates mr ON ca.category = mr.category
ORDER BY ca.category;