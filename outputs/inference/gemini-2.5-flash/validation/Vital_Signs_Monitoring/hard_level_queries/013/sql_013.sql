with "with a multi-trauma diagnosis."
-- This line is not a standard SQL comment and caused a syntax error
-- because BigQuery expected a CTE name like 'multi' to be followed by 'AS'.
-- The fix is to properly comment out this descriptive text
-- so the SQL query starts with valid syntax (e.g., a properly formed WITH clause).

WITH first_icu_stay AS (
    -- Select the first ICU stay for each patient, calculate LOS in hours
    SELECT
        subject_id,
        hadm_id,
        stay_id,
        intime,
        outtime,
        -- Calculate LOS in hours (as requested for 'mean ICU LOS')
        CAST(DATETIME_DIFF(outtime, intime, HOUR) AS NUMERIC) AS los_hours,
        ROW_NUMBER() OVER (PARTITION BY subject_id ORDER BY intime) as rn
    FROM `physionet-data.mimiciv_3_1_icu.icustays`
),
cohort_base AS (
    -- Define the study cohort based on age, gender, first ICU stay, and multi-trauma diagnosis
    SELECT
        p.subject_id,
        fs.hadm_id,
        fs.stay_id,
        p.gender,
        p.anchor_age,
        fs.intime,
        fs.outtime,
        fs.los_hours,
        adm.hospital_expire_flag
    FROM `physionet-data.mimiciv_3_1_hosp.patients` p
    INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` adm
        ON p.subject_id = adm.subject_id
    INNER JOIN first_icu_stay fs
        ON adm.hadm_id = fs.hadm_id
    WHERE fs.rn = 1 -- Ensures it's the patient's first ICU stay
    AND p.gender = 'M'
    AND p.anchor_age BETWEEN 68 AND 78 -- Age filter
    -- Multi-trauma filter: Patients with ICD-10 'T07' or ICD-9 '959%' codes
    AND EXISTS (
        SELECT 1
        FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` di
        WHERE di.hadm_id = adm.hadm_id
        AND (
            (di.icd_version = 10 AND di.icd_code = 'T07') -- ICD-10 Unspecified multiple injuries
            OR (di.icd_version = 9 AND di.icd_code LIKE '959%') -- ICD-9 Unspecified injury, multiple sites (e.g., 959.9)
        )
    )
),
vital_signs_raw AS (
    -- Extract relevant vital sign measurements within the first 24 hours of ICU stay for the cohort
    SELECT
        cb.subject_id,
        cb.hadm_id,
        cb.stay_id,
        cb.intime, -- Keep intime for relative time calculation
        ce.charttime,
        ce.itemid,
        ce.valuenum
    FROM cohort_base cb
    INNER JOIN `physionet-data.mimiciv_3_1_icu.chartevents` ce
        ON cb.stay_id = ce.stay_id
    WHERE ce.valuenum IS NOT NULL -- Exclude null values
    -- Filter for measurements within the first 24 hours of ICU admission
    AND ce.charttime BETWEEN cb.intime AND DATETIME_ADD(cb.intime, INTERVAL 24 HOUR)
    AND ce.itemid IN (
        220045, -- Heart Rate
        220050, -- SBP
        220210, -- Respiratory Rate
        223761  -- Temperature Celsius
    )
),
hourly_instability_flags AS (
    -- Calculate hourly instability flags (1 if any measurement in that hour was abnormal, 0 otherwise)
    SELECT
        subject_id,
        hadm_id,
        stay_id,
        -- Calculate the 0-indexed hour of the stay (0 to 23 for the first 24 hours)
        CAST(FLOOR(DATETIME_DIFF(charttime, intime, MINUTE) / 60) AS INT64) AS hour_of_stay,
        MAX(CASE WHEN itemid = 220045 AND (valuenum < 60 OR valuenum > 100) THEN 1 ELSE 0 END) AS hr_unstable_flag,
        MAX(CASE WHEN itemid = 220050 AND (valuenum < 90 OR valuenum > 140) THEN 1 ELSE 0 END) AS sbp_unstable_flag,
        MAX(CASE WHEN itemid = 220210 AND (valuenum < 12 OR valuenum > 20) THEN 1 ELSE 0 END) AS rr_unstable_flag,
        MAX(CASE WHEN itemid = 223761 AND (valuenum < 36.0 OR valuenum > 38.0) THEN 1 ELSE 0 END) AS temp_unstable_flag
    FROM vital_signs_raw
    -- Ensure hour_of_stay is within the 0-23 range. This implicitly handles `charttime` already being within 24h.
    WHERE DATETIME_DIFF(charttime, intime, MINUTE) >= 0
    AND DATETIME_DIFF(charttime, intime, MINUTE) < 24 * 60
    GROUP BY subject_id, hadm_id, stay_id, hour_of_stay
),
patient_instability_score AS (
    -- Calculate the total instability score for each patient's ICU stay
    SELECT
        hif.subject_id,
        hif.hadm_id,
        hif.stay_id,
        cb.los_hours,
        cb.hospital_expire_flag,
        -- Sum of hourly flags: A higher score means more hours with vital sign abnormalities
        -- This sums the number of unstable vital signs per hour, aggregated over 24 hours.
        CAST(SUM(hr_unstable_flag + sbp_unstable_flag + rr_unstable_flag + temp_unstable_flag) AS NUMERIC) AS instability_score
    FROM hourly_instability_flags hif
    INNER JOIN cohort_base cb
        ON hif.stay_id = cb.stay_id
    GROUP BY hif.subject_id, hif.hadm_id, hif.stay_id, cb.los_hours, cb.hospital_expire_flag
),
instability_ranks AS (
    -- Assign quartiles and deciles based on the instability score
    SELECT
        *,
        NTILE(4) OVER (ORDER BY instability_score DESC) AS instability_quartile,
        NTILE(10) OVER (ORDER BY instability_score DESC) AS instability_decile
    FROM patient_instability_score
),
-- First part of the final output: Summary by instability quartile
quartile_output AS (
    SELECT
        CAST(instability_quartile AS STRING) AS category,
        'Quartile ' || CAST(instability_quartile AS STRING) AS description,
        COUNT(DISTINCT stay_id) AS patient_count,
        AVG(instability_score) AS mean_instability_score,
        AVG(los_hours) AS mean_icu_los_hours,
        SAFE_DIVIDE(SUM(hospital_expire_flag), COUNT(DISTINCT stay_id)) AS mortality_rate,
        NULL AS mean_tachycardia_episodes, -- Null for aggregated columns not applicable to this grouping
        NULL AS mean_hypotension_episodes,
        NULL AS mean_tachypnea_episodes
    FROM instability_ranks
    GROUP BY instability_quartile
),
-- Prepare data to calculate detailed vital sign episodes for the top decile
top_decile_vital_events_per_minute AS (
    SELECT
        ir.subject_id,
        ir.hadm_id,
        ir.stay_id,
        -- Truncate charttime to the minute to count distinct "episodes" per minute
        DATETIME_TRUNC(vsr.charttime, MINUTE) AS event_minute,
        -- Flags for specific events, maximum within that minute
        MAX(CASE WHEN vsr.itemid = 220045 AND vsr.valuenum > 100 THEN 1 ELSE 0 END) AS tachycardia_flag,
        MAX(CASE WHEN vsr.itemid = 220050 AND vsr.valuenum < 90 THEN 1 ELSE 0 END) AS hypotension_flag,
        MAX(CASE WHEN vsr.itemid = 220210 AND vsr.valuenum > 20 THEN 1 ELSE 0 END) AS tachypnea_flag
    FROM instability_ranks ir
    INNER JOIN vital_signs_raw vsr
        ON ir.stay_id = vsr.stay_id
    WHERE ir.instability_decile = 1 -- Only consider the top decile
    GROUP BY ir.subject_id, ir.hadm_id, ir.stay_id, event_minute
),
top_decile_episode_counts_per_patient AS (
    -- Sum the minute-flags to get total episodes per patient in the top decile
    SELECT
        subject_id,
        hadm_id,
        stay_id,
        SUM(tachycardia_flag) AS tachycardia_episode_count,
        SUM(hypotension_flag) AS hypotension_episode_count,
        SUM(tachypnea_flag) AS tachypnea_episode_count
    FROM top_decile_vital_events_per_minute
    GROUP BY subject_id, hadm_id, stay_id
),
-- Second part of the final output: Summary for the top decile
top_decile_output AS (
    SELECT
        'Top 10%' AS category,
        'Decile 1 (Highest Instability Scores)' AS description,
        COUNT(DISTINCT tdec.stay_id) AS patient_count,
        AVG(ir.instability_score) AS mean_instability_score,
        AVG(ir.los_hours) AS mean_icu_los_hours,
        SAFE_DIVIDE(SUM(ir.hospital_expire_flag), COUNT(DISTINCT tdec.stay_id)) AS mortality_rate,
        AVG(tdec.tachycardia_episode_count) AS mean_tachycardia_episodes,
        AVG(tdec.hypotension_episode_count) AS mean_hypotension_episodes,
        AVG(tdec.tachypnea_episode_count) AS mean_tachypnea_episodes
    FROM top_decile_episode_counts_per_patient tdec
    INNER JOIN instability_ranks ir
        ON tdec.stay_id = ir.stay_id
    WHERE ir.instability_decile = 1
    GROUP BY category, description
)
-- Combine both result sets and order them for logical presentation
SELECT * FROM quartile_output
UNION ALL
SELECT * FROM top_decile_output
ORDER BY
    CASE
        WHEN category = '1' THEN 1
        WHEN category = '2' THEN 2
        WHEN category = '3' THEN 3
        WHEN category = '4' THEN 4
        WHEN category = 'Top 10%' THEN 5
        ELSE 6 -- Fallback, should not happen with current categories
    END;