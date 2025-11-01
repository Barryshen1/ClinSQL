WITH patients_cohort AS (
    SELECT
        p.subject_id,
        p.gender,
        p.anchor_age,
        adm.hadm_id,
        icu.stay_id,
        icu.intime
    FROM
        `physionet-data.mimiciv_3_1_hosp.patients` p
    INNER JOIN
        `physionet-data.mimiciv_3_1_hosp.admissions` adm
        ON p.subject_id = adm.subject_id
    INNER JOIN
        `physionet-data.mimiciv_3_1_icu.icustays` icu
        ON adm.hadm_id = icu.hadm_id
    WHERE
        p.gender = 'F'
        AND p.anchor_age BETWEEN 62 AND 72
),
-- Step 2: Identify admissions with an AKI diagnosis (using ICD codes)
aki_admissions AS (
    SELECT DISTINCT
        dia.hadm_id,
        1 AS has_aki
    FROM
        `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` dia
    WHERE
        -- ICD-9 codes for Acute Kidney Failure (584.x)
        (dia.icd_version = 9 AND dia.icd_code LIKE '584%')
        -- ICD-10 codes for Acute Kidney Failure (N17.x)
        OR (dia.icd_version = 10 AND dia.icd_code LIKE 'N17%')
),
-- Step 3: Extract first 24h temperature measurements for the cohort, convert to Celsius
first_24h_temps AS (
    SELECT
        pc.subject_id,
        pc.hadm_id,
        pc.stay_id,
        ce.charttime,
        CASE
            WHEN di.itemid = 223761 AND ce.valuenum IS NOT NULL THEN (ce.valuenum - 32) * 5 / 9 -- Convert Fahrenheit to Celsius
            WHEN di.itemid = 223762 AND ce.valuenum IS NOT NULL THEN ce.valuenum -- Temperature is already in Celsius
            ELSE NULL
        END AS temp_celsius
    FROM
        patients_cohort pc
    INNER JOIN
        `physionet-data.mimiciv_3_1_icu.chartevents` ce
        ON pc.subject_id = ce.subject_id AND pc.stay_id = ce.stay_id
    INNER JOIN
        `physionet-data.mimiciv_3_1_icu.d_items` di
        ON ce.itemid = di.itemid
    WHERE
        ce.itemid IN (223761, 223762) -- Filter for Temperature itemids
        AND ce.valuenum IS NOT NULL
        AND ce.charttime BETWEEN pc.intime AND TIMESTAMP_ADD(pc.intime, INTERVAL 24 HOUR)
        -- Filter out implausible temperature values after conversion or direct Celsius
        AND (
            (di.itemid = 223761 AND ce.valuenum BETWEEN 70 AND 110) -- Reasonable Fahrenheit range before conversion
            OR (di.itemid = 223762 AND ce.valuenum BETWEEN 20 AND 45) -- Reasonable Celsius range
        )
),
-- Step 4: Categorize temperatures and combine with AKI status for each measurement
categorized_temps_with_aki AS (
    SELECT
        f24t.subject_id,
        f24t.hadm_id,
        f24t.stay_id,
        f24t.charttime,
        f24t.temp_celsius,
        CASE
            WHEN f24t.temp_celsius < 36.0 THEN '<36.0 °C'
            WHEN f24t.temp_celsius >= 36.0 AND f24t.temp_celsius <= 37.9 THEN '36.0-37.9 °C'
            WHEN f24t.temp_celsius >= 38.0 THEN '>=38.0 °C'
            ELSE 'Unknown/Uncategorized'
        END AS temperature_category,
        COALESCE(aa.has_aki, 0) AS has_aki_admission_flag -- 1 if AKI occurred in this admission, 0 otherwise
    FROM
        first_24h_temps f24t
    LEFT JOIN
        aki_admissions aa
        ON f24t.hadm_id = aa.hadm_id
    WHERE f24t.temp_celsius IS NOT NULL -- Ensure only valid temperatures are included for categorization
)
-- Step 5: Calculate requested statistics per temperature category
SELECT
    temperature_category,
    COUNT(temp_celsius) AS num_measurements,
    ROUND(AVG(temp_celsius), 2) AS mean_temperature_celsius,
    ROUND(
        PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY temp_celsius), 2
    ) AS median_temperature_celsius,
    ROUND(
        (PERCENTILE_CONT(0.75) WITHIN GROUP (ORDER BY temp_celsius)) -
        (PERCENTILE_CONT(0.25) WITHIN GROUP (ORDER BY temp_celsius)), 2
    ) AS iqr_temperature_celsius,
    ROUND(AVG(has_aki_admission_flag) * 100, 2) AS aki_rate_percent
FROM
    categorized_temps_with_aki
GROUP BY
    temperature_category
ORDER BY
    CASE
        WHEN temperature_category = '<36.0 °C' THEN 1
        WHEN temperature_category = '36.0-37.9 °C' THEN 2
        WHEN temperature_category = '>=38.0 °C' THEN 3
        ELSE 4
    END;