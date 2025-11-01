WITH
-- Step 1: Define the patient cohort of male patients aged 74-84 at ICU admission.
cohort AS (
    SELECT
        p.subject_id,
        icu.hadm_id,
        icu.stay_id,
        icu.intime,
        icu.los
    FROM `physionet-data.mimiciv_3_1_icu.icustays` AS icu
    INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` AS p
        ON icu.subject_id = p.subject_id
    WHERE
        p.gender = 'M'
        -- Calculate age at the time of ICU admission
        AND (p.anchor_age + EXTRACT(YEAR FROM icu.intime) - p.anchor_year) BETWEEN 74 AND 84
),

-- Step 2: Gather all relevant vital signs from the first 48 hours of the ICU stay.
vitals_first_48h AS (
    SELECT
        c.stay_id,
        ce.charttime,
        ce.itemid,
        ce.valuenum
    FROM `physionet-data.mimiciv_3_1_icu.chartevents` AS ce
    INNER JOIN cohort AS c
        ON ce.stay_id = c.stay_id
    WHERE
        ce.charttime BETWEEN c.intime AND TIMESTAMP_ADD(c.intime, INTERVAL 48 HOUR)
        AND ce.valuenum IS NOT NULL
        AND ce.itemid IN (
            223762, -- Temperature Celsius
            223761, -- Temperature Fahrenheit
            220277, -- O2 saturation pulseoxymetry
            220210, -- Respiratory Rate
            224690  -- Respiratory Rate (Total)
        )
),

-- Step 3: For each hour, determine if any instability criteria were met.
hourly_flags AS (
    SELECT
        stay_id,
        TIMESTAMP_TRUNC(charttime, HOUR) AS hour_bucket,
        MAX(CASE
            WHEN itemid = 223762 AND valuenum > 38.5 THEN 1       -- Temp C
            WHEN itemid = 223761 AND (valuenum - 32) * 5 / 9 > 38.5 THEN 1 -- Temp F
            ELSE 0
        END) AS has_fever,
        MAX(CASE
            WHEN itemid = 220277 AND valuenum < 90 THEN 1 -- SpO2
            ELSE 0
        END) AS has_hypoxemia,
        MAX(CASE
            WHEN itemid IN (220210, 224690) AND valuenum > 20 THEN 1 -- Resp Rate
            ELSE 0
        END) AS has_tachypnea
    FROM vitals_first_48h
    GROUP BY
        stay_id,
        hour_bucket
),

-- Step 4: Sum the hourly flags to get total hours for each condition and overall instability per stay.
instability_scores AS (
    SELECT
        stay_id,
        SUM(has_fever) AS fever_hours,
        SUM(has_hypoxemia) AS hypoxemia_hours,
        SUM(has_tachypnea) AS tachypnea_hours,
        SUM(CASE
            WHEN has_fever = 1 OR has_hypoxemia = 1 OR has_tachypnea = 1 THEN 1
            ELSE 0
        END) AS total_instability_hours
    FROM hourly_flags
    GROUP BY
        stay_id
),

-- Step 5: Join instability scores with cohort and admission data for outcomes.
instability_with_outcomes AS (
    SELECT
        sc.stay_id,
        c.los,
        a.hospital_expire_flag,
        sc.fever_hours,
        sc.hypoxemia_hours,
        sc.tachypnea_hours,
        sc.total_instability_hours
    FROM instability_scores AS sc
    INNER JOIN cohort AS c
        ON sc.stay_id = c.stay_id
    INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` AS a
        ON c.hadm_id = a.hadm_id
),

-- Step 6: Calculate the 90th percentile threshold and the aggregated stats for the top decile.
percentile_threshold AS (
    SELECT
        DISTINCT PERCENTILE_CONT(total_instability_hours, 0.9) OVER() AS percentile_90
    FROM instability_with_outcomes
),

top_decile_stats AS (
    SELECT
        COUNT(io.stay_id) AS n_stays,
        AVG(io.los) AS mean_los_days,
        AVG(io.hospital_expire_flag) * 100 AS mortality_pct,
        AVG(io.fever_hours) AS mean_fever_hours,
        AVG(io.hypoxemia_hours) AS mean_hypoxemia_hours,
        AVG(io.tachypnea_hours) AS mean_tachypnea_hours
    FROM instability_with_outcomes AS io, percentile_threshold AS pt
    WHERE io.total_instability_hours >= pt.percentile_90
)


-- Final Step: Format and present the two-part answer.
SELECT
    '90th-percentile first-48-h instability (hours)' AS metric,
    CAST(t.percentile_90 AS STRING) AS value
FROM percentile_threshold AS t

UNION ALL

SELECT '-- Top Decile Metrics --' AS metric, NULL AS value

UNION ALL

SELECT 'n (stays)', CAST(s.n_stays AS STRING) FROM top_decile_stats AS s
UNION ALL
SELECT 'mean ICU LOS (days)', CAST(ROUND(s.mean_los_days, 1) AS STRING) FROM top_decile_stats AS s
UNION ALL
SELECT 'mortality (%)', CAST(ROUND(s.mortality_pct, 1) AS STRING) FROM top_decile_stats AS s
UNION ALL
SELECT 'mean hours fever (>38.5°C)', CAST(ROUND(s.mean_fever_hours, 1) AS STRING) FROM top_decile_stats AS s
UNION ALL
SELECT 'mean hours hypoxemia (SpO2<90%)', CAST(ROUND(s.mean_hypoxemia_hours, 1) AS STRING) FROM top_decile_stats AS s
UNION ALL
SELECT 'mean hours tachypnea (RR>20)', CAST(ROUND(s.mean_tachypnea_hours, 1) AS STRING) FROM top_decile_stats AS s;