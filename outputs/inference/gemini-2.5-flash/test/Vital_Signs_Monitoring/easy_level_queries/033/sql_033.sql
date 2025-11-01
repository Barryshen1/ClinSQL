WITH patient_cohort AS (
    -- Identify female patients aged 45-55 at the time of hospital admission
    SELECT
        p.subject_id,
        adm.hadm_id,
        p.gender,
        (p.anchor_age + (EXTRACT(YEAR FROM adm.admittime) - p.anchor_year)) AS age_at_admission
    FROM
        `physionet-data.mimiciv_3_1_hosp`.patients p
    INNER JOIN
        `physionet-data.mimiciv_3_1_hosp`.admissions adm
        ON p.subject_id = adm.subject_id
    WHERE
        p.gender = 'F'
        AND (p.anchor_age + (EXTRACT(YEAR FROM adm.admittime) - p.anchor_year)) BETWEEN 45 AND 55
),
icu_heart_rates AS (
    -- Retrieve heart rate measurements for the identified cohort on ICU day 2+
    SELECT
        ce.valuenum AS heart_rate
    FROM
        patient_cohort pc
    INNER JOIN
        `physionet-data.mimiciv_3_1_icu`.icustays icu
        ON pc.subject_id = icu.subject_id AND pc.hadm_id = icu.hadm_id
    INNER JOIN
        `physionet-data.mimiciv_3_1_icu`.chartevents ce
        ON icu.subject_id = ce.subject_id
        AND icu.hadm_id = ce.hadm_id
        AND icu.stay_id = ce.stay_id
    WHERE
        ce.itemid = 220045 -- ItemID for 'Heart Rate'
        AND ce.valuenum IS NOT NULL -- Ensure numeric value exists
        AND ce.valuenum > 0          -- Filter out biologically impossible low values
        AND ce.valuenum < 300        -- Filter out biologically impossible high values
        -- Filter for measurements on ICU day 2 onwards
        -- DATE_DIFF = 0 means day 1, DATE_DIFF = 1 means day 2, etc.
        AND DATE_DIFF(DATE(ce.charttime), DATE(icu.intime), DAY) >= 1
)
-- Calculate the Interquartile Range (IQR) of heart rate
SELECT
    PERCENTILE_CONT(heart_rate, 0.75) OVER() - PERCENTILE_CONT(heart_rate, 0.25) OVER() AS iqr_heart_rate
FROM
    icu_heart_rates
LIMIT 1; -- We only need one row as the IQR is for the entire set;