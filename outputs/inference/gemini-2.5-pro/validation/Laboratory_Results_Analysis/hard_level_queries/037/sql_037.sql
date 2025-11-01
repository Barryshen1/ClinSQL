WITH
-- Step 1: Identify the cohort of male patients aged 70-80 with a hemorrhagic stroke diagnosis.
cohort_hadm AS (
    SELECT DISTINCT
        adm.hadm_id,
        adm.admittime,
        adm.dischtime,
        adm.hospital_expire_flag
    FROM
        `physionet-data.mimiciv_3_1_hosp.patients` AS pat
    JOIN
        `physionet-data.mimiciv_3_1_hosp.admissions` AS adm
        ON pat.subject_id = adm.subject_id
    JOIN
        `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` AS dx
        ON adm.hadm_id = dx.hadm_id
    WHERE
        pat.gender = 'M'
        AND pat.anchor_age BETWEEN 70 AND 80
        AND (
            -- Hemorrhagic stroke ICD-9 codes
            (dx.icd_version = 9 AND SUBSTR(dx.icd_code, 1, 3) IN ('430', '431', '432')) OR
            -- Hemorrhagic stroke ICD-10 codes
            (dx.icd_version = 10 AND SUBSTR(dx.icd_code, 1, 3) IN ('I60', 'I61', 'I62'))
        )
),

-- Step 2: Calculate the "lab instability score" for each patient in the cohort.
-- The score is the count of 'abnormal' labs in the first 48 hours of admission.
cohort_scores AS (
    SELECT
        ch.hadm_id,
        COUNT(le.labevent_id) AS first_48hr_instability_score
    FROM
        cohort_hadm AS ch
    LEFT JOIN
        `physionet-data.mimiciv_3_1_hosp.labevents` AS le
        ON ch.hadm_id = le.hadm_id
        -- Filter for abnormal labs within the first 48 hours
        AND le.flag = 'abnormal'
        AND le.charttime BETWEEN ch.admittime AND TIMESTAMP_ADD(ch.admittime, INTERVAL 48 HOUR)
    GROUP BY
        ch.hadm_id
),

-- Step 3a: Calculate the 25th percentile of the instability score for the cohort.
cohort_percentile AS (
    SELECT
        APPROX_QUANTILES(first_48hr_instability_score, 100)[OFFSET(25)] AS score_25th_percentile
    FROM
        cohort_scores
),

-- Step 3b: Calculate mean LOS and mortality for the cohort.
cohort_main_stats AS (
    SELECT
        AVG(TIMESTAMP_DIFF(dischtime, admittime, DAY)) AS cohort_mean_los_days,
        AVG(hospital_expire_flag) AS cohort_in_hospital_mortality
    FROM
        cohort_hadm
),

-- Step 4: Calculate the critical lab event rates for the cohort vs. the general inpatient population.
-- The rate is defined as (abnormal labs in first 48h) / (total labs in first 48h).
comparison_rates AS (
    SELECT
        SAFE_DIVIDE(
            COUNTIF(le.flag = 'abnormal'),
            COUNT(le.labevent_id)
        ) AS general_critical_lab_rate,
        SAFE_DIVIDE(
            COUNTIF(le.flag = 'abnormal' AND ch.hadm_id IS NOT NULL),
            COUNTIF(ch.hadm_id IS NOT NULL)
        ) AS cohort_critical_lab_rate
    FROM
        `physionet-data.mimiciv_3_1_hosp.admissions` AS adm
    JOIN
        `physionet-data.mimiciv_3_1_hosp.labevents` AS le
        ON adm.hadm_id = le.hadm_id
    LEFT JOIN
        cohort_hadm AS ch ON adm.hadm_id = ch.hadm_id
    WHERE
        -- Only consider labs within the first 48 hours of any admission
        le.charttime BETWEEN adm.admittime AND TIMESTAMP_ADD(adm.admittime, INTERVAL 48 HOUR)
)

-- Step 5: Combine all calculated metrics into a single output row.
SELECT
    cp.score_25th_percentile,
    cr.cohort_critical_lab_rate,
    cr.general_critical_lab_rate,
    cs.cohort_mean_los_days,
    cs.cohort_in_hospital_mortality
FROM
    cohort_percentile AS cp
CROSS JOIN
    cohort_main_stats AS cs
CROSS JOIN
    comparison_rates AS cr;