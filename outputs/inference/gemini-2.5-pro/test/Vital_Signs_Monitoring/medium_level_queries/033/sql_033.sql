WITH icu_cohort AS (
    -- Step 1: Identify male ICU patients aged 62-72
    SELECT
        p.subject_id,
        icu.hadm_id,
        icu.stay_id
    FROM
        `physionet-data.mimiciv_3_1_hosp.patients` AS p
    INNER JOIN
        `physionet-data.mimiciv_3_1_icu.icustays` AS icu
        ON p.subject_id = icu.subject_id
    WHERE
        p.gender = 'M'
        -- Calculate age at the time of ICU admission and filter
        AND (DATETIME_DIFF(icu.intime, DATETIME(p.anchor_year, 1, 1, 0, 0, 0), YEAR) + p.anchor_age) BETWEEN 62 AND 72
),

mean_hr_per_stay AS (
    -- Step 2: Calculate mean heart rate for each ICU stay
    SELECT
        stay_id,
        AVG(valuenum) AS mean_hr
    FROM
        `physionet-data.mimiciv_3_1_icu.chartevents`
    WHERE
        itemid = 220045 -- Heart Rate
        AND valuenum > 0 AND valuenum < 300 -- Filter for plausible values
    GROUP BY
        stay_id
),

ami_admissions AS (
    -- Step 3: Identify hospital admissions with a diagnosis of Acute MI
    SELECT DISTINCT
        hadm_id
    FROM
        `physionet-data.mimiciv_3_1_hosp.diagnoses_icd`
    WHERE
        -- ICD-9 codes for Acute Myocardial Infarction
        (icd_version = 9 AND SUBSTR(icd_code, 1, 3) = '410')
        -- ICD-10 codes for Acute Myocardial Infarction
        OR (icd_version = 10 AND (SUBSTR(icd_code, 1, 3) = 'I21' OR SUBSTR(icd_code, 1, 3) = 'I22'))
)

-- Step 4 & 5: Combine data, categorize, and aggregate results
SELECT
    hr_category,
    COUNT(stays.stay_id) AS number_of_icu_stays,
    AVG(CASE WHEN ami.hadm_id IS NOT NULL THEN 1 ELSE 0 END) * 100 AS percent_with_acute_mi
FROM (
    -- Create a subquery to join cohort with HR and categorize
    SELECT
        cohort.stay_id,
        cohort.hadm_id,
        CASE
            WHEN hr.mean_hr < 60 THEN '<60'
            WHEN hr.mean_hr >= 60 AND hr.mean_hr < 100 THEN '60-99'
            WHEN hr.mean_hr >= 100 AND hr.mean_hr < 120 THEN '100-119'
            WHEN hr.mean_hr >= 120 THEN '>=120'
        END AS hr_category
    FROM
        icu_cohort AS cohort
    INNER JOIN
        mean_hr_per_stay AS hr
        ON cohort.stay_id = hr.stay_id
) AS stays
LEFT JOIN
    ami_admissions AS ami
    ON stays.hadm_id = ami.hadm_id
GROUP BY
    hr_category
ORDER BY
    -- Order the results logically by HR category
    CASE hr_category
        WHEN '<60' THEN 1
        WHEN '60-99' THEN 2
        WHEN '100-119' THEN 3
        WHEN '>=120' THEN 4
    END;