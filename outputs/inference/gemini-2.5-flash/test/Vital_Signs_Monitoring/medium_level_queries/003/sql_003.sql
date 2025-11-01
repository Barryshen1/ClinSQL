WITH cohort_icu_stays AS (
    -- Step 1: Identify the cohort of male ICU patients aged 71-81
    SELECT
        p.subject_id,
        ad.hadm_id,
        icu.stay_id,
        icu.intime
    FROM
        `physionet-data.mimiciv_3_1_hosp.patients` p
    JOIN
        `physionet-data.mimiciv_3_1_hosp.admissions` ad
        ON p.subject_id = ad.subject_id
    JOIN
        `physionet-data.mimiciv_3_1_icu.icustays` icu
        ON ad.hadm_id = icu.hadm_id
    WHERE
        p.gender = 'M'
        AND p.anchor_age BETWEEN 71 AND 81
),
temperature_measurements AS (
    -- Step 2: Extract and filter temperature measurements for the cohort
    SELECT
        ce.stay_id,
        ce.charttime,
        ce.valuenum
    FROM
        `physionet-data.mimiciv_3_1_icu.chartevents` ce
    JOIN
        `physionet-data.mimiciv_3_1_icu.d_items` di
        ON ce.itemid = di.itemid
    WHERE
        di.label = 'Temperature C' -- Focus on Celsius measurements
        AND ce.valuenum IS NOT NULL
        AND ce.valuenum > 20 AND ce.valuenum < 45 -- Filter for physiologically plausible values
),
cohort_avg_temp AS (
    -- Step 3: Calculate the average temperature over the first 48 hours for each ICU stay
    SELECT
        cis.subject_id,
        cis.hadm_id,
        cis.stay_id,
        AVG(tm.valuenum) AS avg_temp_48h
    FROM
        cohort_icu_stays cis
    JOIN
        temperature_measurements tm
        ON cis.stay_id = tm.stay_id
    WHERE
        tm.charttime BETWEEN cis.intime AND DATETIME_ADD(cis.intime, INTERVAL 48 HOUR)
    GROUP BY
        cis.subject_id,
        cis.hadm_id,
        cis.stay_id
    HAVING
        AVG(tm.valuenum) IS NOT NULL -- Ensure there's at least one valid temp measurement
),
stay_categorized_temp AS (
    -- Step 4: Categorize each stay based on its average 48-hour temperature
    SELECT
        cat.subject_id,
        cat.hadm_id,
        cat.stay_id,
        cat.avg_temp_48h,
        CASE
            WHEN cat.avg_temp_48h < 36.0 THEN 'Hypothermia (<36.0)'
            WHEN cat.avg_temp_48h >= 36.0 AND cat.avg_temp_48h <= 37.9 THEN 'Normothermia (36.0-37.9)'
            WHEN cat.avg_temp_48h >= 38.0 THEN 'Hyperthermia (>=38.0)'
            ELSE 'Uncategorized' -- Should not be reached if avg_temp_48h is not NULL
        END AS temp_category
    FROM
        cohort_avg_temp cat
),
stay_mi_status AS (
    -- Step 5: Determine if each admission had a Myocardial Infarction diagnosis
    SELECT DISTINCT
        stc.stay_id,
        1 AS has_mi_diagnosis
    FROM
        stay_categorized_temp stc
    JOIN
        `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` di
        ON stc.hadm_id = di.hadm_id
    WHERE
        (di.icd_version = 9 AND di.icd_code LIKE '410%') -- ICD-9 codes for MI
        OR (di.icd_version = 10 AND di.icd_code LIKE 'I21%') -- ICD-10 codes for MI
)
-- Step 6: Final aggregation to report mean, median, IQR, and MI rate per category
SELECT
    sct.temp_category,
    COUNT(DISTINCT sct.stay_id) AS num_stays,
    ROUND(CAST(AVG(sct.avg_temp_48h) AS NUMERIC), 2) AS mean_avg_temp_c,
    ROUND(CAST(APPROX_QUANTILES(sct.avg_temp_48h, 100)[OFFSET(50)] AS NUMERIC), 2) AS median_avg_temp_c,
    ROUND(CAST(APPROX_QUANTILES(sct.avg_temp_48h, 100)[OFFSET(75)] - APPROX_QUANTILES(sct.avg_temp_48h, 100)[OFFSET(25)] AS NUMERIC), 2) AS iqr_avg_temp_c,
    ROUND(CAST(SUM(COALESCE(sms.has_mi_diagnosis, 0)) * 100.0 / COUNT(DISTINCT sct.stay_id) AS NUMERIC), 2) AS mi_rate
FROM
    stay_categorized_temp sct
LEFT JOIN
    stay_mi_status sms
    ON sct.stay_id = sms.stay_id
GROUP BY
    sct.temp_category
ORDER BY
    CASE
        WHEN sct.temp_category = 'Hypothermia (<36.0)' THEN 1
        WHEN sct.temp_category = 'Normothermia (36.0-37.9)' THEN 2
        WHEN sct.temp_category = 'Hyperthermia (>=38.0)' THEN 3
        ELSE 4 -- For any unexpected categories
    END;