WITH 
-- Step 1: Get ICU stays with patient demographics and age
icu_patients AS (
    SELECT 
        i.subject_id,
        i.hadm_id,
        i.stay_id,
        i.intime,
        i.outtime,
        p.gender,
        p.anchor_year,
        p.anchor_age,
        a.admittime,
        -- Compute age at admission
        EXTRACT(YEAR FROM a.admittime) - (p.anchor_year - p.anchor_age) AS age_at_admission
    FROM `physionet-data.mimiciv_3_1_icu.icustays` i
    INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a 
        ON i.subject_id = a.subject_id AND i.hadm_id = a.hadm_id
    INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` p 
        ON i.subject_id = p.subject_id
    WHERE p.gender = 'F'
      AND EXTRACT(YEAR FROM a.admittime) - (p.anchor_year - p.anchor_age) BETWEEN 89 AND 99
),
-- Step 2: Get temperature itemids
temp_items AS (
    SELECT itemid
    FROM `physionet-data.mimiciv_3_1_icu.d_items`
    WHERE category = 'Temperature'
      AND linksto = 'chartevents'
      AND unitname IN ('C', '°C', 'Celsius')   -- ensure unit is Celsius
),
-- Step 3: Get temperature measurements
temp_measurements AS (
    SELECT 
        c.subject_id,
        c.hadm_id,
        c.stay_id,
        c.charttime,
        c.valuenum,
        -- Categorize temperature
        CASE 
            WHEN c.valuenum < 36 THEN '<36'
            WHEN c.valuenum BETWEEN 36 AND 37.9 THEN '36-37.9'
            WHEN c.valuenum >= 38 THEN '>=38'
        END AS temp_category
    FROM `physionet-data.mimiciv_3_1_icu.chartevents` c
    INNER JOIN temp_items t ON c.itemid = t.itemid
    INNER JOIN icu_patients ip 
        ON c.subject_id = ip.subject_id 
        AND c.hadm_id = ip.hadm_id 
        AND c.stay_id = ip.stay_id
    WHERE c.valuenum BETWEEN 30 AND 45   -- exclude outliers
      AND c.valuenum IS NOT NULL
      AND c.charttime BETWEEN ip.intime AND ip.outtime  -- ensure within ICU stay
),
-- Step 4: Get MI diagnoses per patient per admission
mi_diagnoses AS (
    SELECT 
        d.subject_id,
        d.hadm_id,
        -- Mark if any MI diagnosis in this admission
        MAX(CASE 
            WHEN (d.icd_version = 10 AND d.icd_code LIKE 'I21%') 
               OR (d.icd_version = 9 AND d.icd_code LIKE '410%') 
            THEN 1 
            ELSE 0 
        END) AS has_mi
    FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
    INNER JOIN icu_patients ip 
        ON d.subject_id = ip.subject_id 
        AND d.hadm_id = ip.hadm_id
    GROUP BY d.subject_id, d.hadm_id
),
-- Step 5: Combine temperature measurements with MI flag
combined_data AS (
    SELECT 
        tm.subject_id,
        tm.hadm_id,
        tm.stay_id,
        tm.charttime,
        tm.valuenum,
        tm.temp_category,
        -- If the patient has MI in this admission, then flag
        COALESCE(md.has_mi, 0) AS mi_flag
    FROM temp_measurements tm
    LEFT JOIN mi_diagnoses md 
        ON tm.subject_id = md.subject_id 
        AND tm.hadm_id = md.hadm_id
)
-- Step 6: Aggregate per temperature category
SELECT 
    temp_category,
    COUNT(DISTINCT subject_id) AS unique_patients,
    COUNT(*) AS measurement_count,
    AVG(valuenum) AS mean_temp,
    APPROX_QUANTILES(valuenum, 100)[OFFSET(50)] AS median_temp,
    APPROX_QUANTILES(valuenum, 100)[OFFSET(25)] AS q1_temp,
    APPROX_QUANTILES(valuenum, 100)[OFFSET(75)] AS q3_temp,
    (APPROX_QUANTILES(valuenum, 100)[OFFSET(75)] - APPROX_QUANTILES(valuenum, 100)[OFFSET(25)]) AS iqr_temp,
    -- MI rate: proportion of patients with MI in this category
    COUNT(DISTINCT CASE WHEN mi_flag = 1 THEN subject_id END) * 1.0 / COUNT(DISTINCT subject_id) AS mi_rate
FROM combined_data
GROUP BY temp_category
ORDER BY temp_category;