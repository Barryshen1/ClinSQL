WITH eligible_patients AS (
    SELECT
        p.subject_id,
        p.anchor_age
    FROM `physionet-data.mimiciv_3_1_hosp.patients` p
    WHERE p.gender = 'M'
        AND p.anchor_age BETWEEN 71 AND 81
),
icu_stays AS (
    SELECT
        i.subject_id,
        i.hadm_id,
        i.stay_id,
        i.intime,
        i.outtime
    FROM `physionet-data.mimiciv_3_1_icu.icustays` i
    JOIN eligible_patients ep
        ON i.subject_id = ep.subject_id
),
temperature_data AS (
    SELECT
        s.subject_id,
        s.hadm_id,
        s.stay_id,
        s.intime,
        ce.valuenum AS temp_value
    FROM icu_stays s
    JOIN `physionet-data.mimiciv_3_1_icu.chartevents` ce
        ON s.subject_id = ce.subject_id
        AND s.hadm_id = ce.hadm_id
        AND s.stay_id = ce.stay_id
        AND ce.itemid = 223761  -- Core temperature in °C
        AND ce.charttime BETWEEN s.intime AND s.intime + INTERVAL 48 HOUR
    WHERE ce.valuenum IS NOT NULL  -- Exclude null values
),
avg_temp_per_stay AS (
    SELECT
        subject_id,
        hadm_id,
        stay_id,
        AVG(temp_value) AS avg_temp
    FROM temperature_data
    GROUP BY subject_id, hadm_id, stay_id
),
categorized_stays AS (
    SELECT
        subject_id,
        hadm_id,
        stay_id,
        avg_temp,
        CASE
            WHEN avg_temp < 36.0 THEN '<36.0'
            WHEN avg_temp BETWEEN 36.0 AND 37.9 THEN '36.0–37.9'
            WHEN avg_temp >= 38.0 THEN '>=38.0'
        END AS temp_category
    FROM avg_temp_per_stay
),
mi_diagnoses AS (
    SELECT
        d.subject_id,
        d.hadm_id,
        1 AS has_mi
    FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
    WHERE d.icd_code LIKE 'I21%'  -- ICD-10 codes for acute MI
        AND d.icd_version = 10
    GROUP BY d.subject_id, d.hadm_id  -- One row per admission with MI
),
stays_with_mi AS (
    SELECT
        cs.subject_id,
        cs.hadm_id,
        cs.stay_id,
        cs.avg_temp,
        cs.temp_category,
        COALESCE(m.has_mi, 0) AS has_mi
    FROM categorized_stays cs
    LEFT JOIN mi_diagnoses m
        ON cs.subject_id = m.subject_id
        AND cs.hadm_id = m.hadm_id
),
aggregated_data AS (
    SELECT
        temp_category,
        COUNT(*) AS total_stays,
        AVG(avg_temp) AS mean_avg_temp,
        APPROX_QUANTILES(avg_temp, 100)[SAFE_OFFSET(50)] AS median_avg_temp,
        APPROX_QUANTILES(avg_temp, 100)[SAFE_OFFSET(75)] - APPROX_QUANTILES(avg_temp, 100)[SAFE_OFFSET(25)] AS iqr_avg_temp,
        SUM(has_mi) / COUNT(*) AS mi_rate
    FROM stays_with_mi
    GROUP BY temp_category
)
SELECT
    temp_category,
    mean_avg_temp,
    median_avg_temp,
    iqr_avg_temp,
    mi_rate
FROM aggregated_data
ORDER BY 
    CASE temp_category
        WHEN '<36.0' THEN 1
        WHEN '36.0–37.9' THEN 2
        WHEN '>=38.0' THEN 3
    END;