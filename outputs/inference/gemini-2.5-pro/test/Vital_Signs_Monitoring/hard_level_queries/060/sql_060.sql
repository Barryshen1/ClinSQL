WITH icustay_cohort AS (
    SELECT
        icu.subject_id,
        icu.hadm_id,
        icu.stay_id,
        icu.intime,
        icu.los,
        adm.hospital_expire_flag,
        -- Calculate age at ICU admission
        DATETIME_DIFF(icu.intime, DATETIME(p.anchor_year, 1, 1, 0, 0, 0), YEAR) + p.anchor_age AS age_at_icu_intime
    FROM `physionet-data.mimiciv_3_1_icu.icustays` AS icu
    INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` AS p
        ON icu.subject_id = p.subject_id
    INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` AS adm
        ON icu.hadm_id = adm.hadm_id
    WHERE
        p.gender = 'M'
),
-- Filter the cohort to the desired age range
cohort_age_filtered AS (
    SELECT *
    FROM icustay_cohort
    WHERE age_at_icu_intime BETWEEN 78 AND 88
),

-- Identify hospital admissions with a diagnosis of HHS
hhs_hadm_ids AS (
    SELECT DISTINCT hadm_id
    FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd`
    WHERE
        -- ICD-9 code for Hyperosmolarity
        icd_code LIKE '2502%'
        -- ICD-10 codes for Diabetes with hyperosmolarity
        OR icd_code LIKE 'E110%'
        OR icd_code LIKE 'E130%'
        OR icd_code LIKE 'E140%'
),

-- Label patients in the cohort as 'HHS' or 'Control'
cohort_with_groups AS (
    SELECT
        c.stay_id,
        c.los,
        c.intime,
        c.hospital_expire_flag,
        CASE
            WHEN h.hadm_id IS NOT NULL THEN 'HHS'
            ELSE 'Control'
        END AS patient_group
    FROM cohort_age_filtered AS c
    LEFT JOIN hhs_hadm_ids AS h
        ON c.hadm_id = h.hadm_id
),

-- Extract and standardize vital signs from the first 48 hours of ICU stay
vitals_first_48h AS (
    SELECT
        c.stay_id,
        ce.valuenum,
        -- Standardize temperature to Celsius
        CASE
            WHEN ce.itemid = 223762 THEN (ce.valuenum - 32) * 5 / 9 -- Fahrenheit to Celsius
            ELSE ce.valuenum
        END AS value_standardized,
        -- Categorize vital signs
        CASE
            WHEN ce.itemid = 220045 THEN 'HR'
            WHEN ce.itemid = 220210 THEN 'RR'
            WHEN ce.itemid IN (223761, 223762) THEN 'Temp'
            WHEN ce.itemid IN (220179, 220050) THEN 'SBP'
            WHEN ce.itemid = 220277 THEN 'SpO2'
        END AS vital_category
    FROM `physionet-data.mimiciv_3_1_icu.chartevents` AS ce
    INNER JOIN cohort_with_groups AS c
        ON ce.stay_id = c.stay_id
    WHERE
        ce.charttime BETWEEN c.intime AND DATETIME_ADD(c.intime, INTERVAL 48 HOUR)
        AND ce.itemid IN (
            220045, -- Heart Rate
            220210, -- Respiratory Rate
            223761, -- Temperature Celsius
            223762, -- Temperature Fahrenheit
            220179, -- Non Invasive Blood Pressure systolic
            220050, -- Arterial Blood Pressure systolic
            220277  -- O2 saturation pulseoxymetry
        )
        AND ce.valuenum IS NOT NULL
),

-- Flag each vital sign measurement as abnormal or not
abnormal_vitals AS (
    SELECT
        stay_id,
        vital_category,
        CASE
            WHEN vital_category = 'HR' AND (value_standardized < 60 OR value_standardized > 100) THEN 1
            WHEN vital_category = 'RR' AND (value_standardized < 12 OR value_standardized > 20) THEN 1
            WHEN vital_category = 'Temp' AND (value_standardized < 36.0 OR value_standardized > 38.3) THEN 1
            WHEN vital_category = 'SBP' AND (value_standardized < 90 OR value_standardized > 140) THEN 1
            WHEN vital_category = 'SpO2' AND value_standardized < 90 THEN 1
            ELSE 0
        END AS is_abnormal
    FROM vitals_first_48h
),

-- Calculate patient-level scores based on abnormal vitals
patient_level_scores AS (
    SELECT
        stay_id,
        -- Total number of abnormal measurements
        SUM(is_abnormal) AS composite_instability_score,
        -- Number of unique vital sign types that were abnormal
        COUNT(DISTINCT CASE WHEN is_abnormal = 1 THEN vital_category END) AS abnormal_vital_burden
    FROM abnormal_vitals
    GROUP BY stay_id
)

-- Final aggregation to get the statistics for each group
SELECT
    c.patient_group,
    -- Percentiles for Composite Instability Score
    APPROX_QUANTILES(COALESCE(s.composite_instability_score, 0), 100)[OFFSET(25)] AS composite_instability_score_p25,
    APPROX_QUANTILES(COALESCE(s.composite_instability_score, 0), 100)[OFFSET(50)] AS composite_instability_score_median,
    APPROX_QUANTILES(COALESCE(s.composite_instability_score, 0), 100)[OFFSET(75)] AS composite_instability_score_p75,
    -- Percentiles for Abnormal-Vital Burden
    APPROX_QUANTILES(COALESCE(s.abnormal_vital_burden, 0), 100)[OFFSET(25)] AS abnormal_vital_burden_p25,
    APPROX_QUANTILES(COALESCE(s.abnormal_vital_burden, 0), 100)[OFFSET(50)] AS abnormal_vital_burden_median,
    APPROX_QUANTILES(COALESCE(s.abnormal_vital_burden, 0), 100)[OFFSET(75)] AS abnormal_vital_burden_p75,
    -- Mean ICU Length of Stay
    AVG(c.los) AS mean_icu_los_days,
    -- Mortality Rate
    AVG(c.hospital_expire_flag) AS mortality_rate
FROM cohort_with_groups AS c
LEFT JOIN patient_level_scores AS s
    ON c.stay_id = s.stay_id
GROUP BY
    c.patient_group
ORDER BY
    c.patient_group;