WITH base_cohort AS (
    -- Step 1: Define the cohort of female ICU patients aged 49-59
    SELECT
        icu.subject_id,
        icu.hadm_id,
        icu.stay_id,
        icu.intime,
        icu.los,
        adm.hospital_expire_flag
    FROM
        `physionet-data.mimiciv_3_1_icu.icustays` AS icu
    INNER JOIN
        `physionet-data.mimiciv_3_1_hosp.patients` AS pat
        ON icu.subject_id = pat.subject_id
    INNER JOIN
        `physionet-data.mimiciv_3_1_hosp.admissions` AS adm
        ON icu.hadm_id = adm.hadm_id
    WHERE
        pat.gender = 'F'
        AND (pat.anchor_age + EXTRACT(YEAR FROM icu.intime) - pat.anchor_year) BETWEEN 49 AND 59
),

instability_flags AS (
    -- Step 2: For each patient in the cohort, flag vital sign instability in the first 24 hours
    SELECT
        ce.stay_id,
        -- Heart Rate: < 50 or > 120
        MAX(CASE WHEN ce.itemid = 220045 AND (ce.valuenum < 50 OR ce.valuenum > 120) THEN 1 ELSE 0 END) AS hr_unstable,
        -- Mean Arterial Pressure: < 65
        MAX(CASE WHEN ce.itemid IN (220052, 220181, 225312) AND ce.valuenum < 65 THEN 1 ELSE 0 END) AS map_unstable,
        -- Respiratory Rate: < 10 or > 30
        MAX(CASE WHEN ce.itemid = 220210 AND (ce.valuenum < 10 OR ce.valuenum > 30) THEN 1 ELSE 0 END) AS rr_unstable,
        -- SpO2: < 90%
        MAX(CASE WHEN ce.itemid = 220277 AND ce.valuenum < 90 THEN 1 ELSE 0 END) AS spo2_unstable,
        -- Temperature: < 36 C or > 38.5 C (handles both F and C)
        MAX(CASE
            WHEN ce.itemid = 223762 AND (ce.valuenum < 36 OR ce.valuenum > 38.5) THEN 1 -- Temp C
            WHEN ce.itemid = 223761 AND (((ce.valuenum - 32) * 5.0/9.0) < 36 OR ((ce.valuenum - 32) * 5.0/9.0) > 38.5) THEN 1 -- Temp F
            ELSE 0
        END) AS temp_unstable
    FROM
        `physionet-data.mimiciv_3_1_icu.chartevents` AS ce
    INNER JOIN
        base_cohort AS bc
        ON ce.stay_id = bc.stay_id
    WHERE
        ce.charttime BETWEEN bc.intime AND DATETIME_ADD(bc.intime, INTERVAL 24 HOUR)
        AND ce.itemid IN (
            220045, -- Heart Rate
            220052, -- Arterial Blood Pressure mean
            220181, -- Non Invasive Blood Pressure mean
            225312, -- Arterial Blood Pressure mean (Invasive)
            220210, -- Respiratory Rate
            220277, -- O2 saturation pulseoxymetry
            223762, -- Temperature Celsius
            223761  -- Temperature Fahrenheit
        )
        AND ce.valuenum IS NOT NULL
    GROUP BY
        ce.stay_id
),

ranked_cohort AS (
    -- Step 3: Calculate the composite score and rank patients into deciles
    SELECT
        bc.los,
        bc.hospital_expire_flag,
        (
            COALESCE(inf.hr_unstable, 0)
            + COALESCE(inf.map_unstable, 0)
            + COALESCE(inf.rr_unstable, 0)
            + COALESCE(inf.spo2_unstable, 0)
            + COALESCE(inf.temp_unstable, 0)
        ) * 20 AS composite_score,
        NTILE(10) OVER (ORDER BY (
            COALESCE(inf.hr_unstable, 0)
            + COALESCE(inf.map_unstable, 0)
            + COALESCE(inf.rr_unstable, 0)
            + COALESCE(inf.spo2_unstable, 0)
            + COALESCE(inf.temp_unstable, 0)
        ) DESC, bc.stay_id) AS score_decile -- stay_id breaks ties
    FROM
        base_cohort AS bc
    LEFT JOIN
        instability_flags AS inf
        ON bc.stay_id = inf.stay_id
),

percentile_calculation AS (
    -- Part 1: Calculate the percentile of a score of 70
    SELECT
        -- A score of 70 falls in the bucket of scores <= 80, but its percentile
        -- is defined as P(score <= 70). Since scores are in increments of 20,
        -- this is the same as P(score <= 60). This finds the max cumulative distribution
        -- for any score <= 70, which gives the correct percentile.
        MAX(CUME_DIST() OVER (ORDER BY composite_score)) * 100 AS percentile_for_score_70
    FROM
        ranked_cohort
    WHERE
        composite_score <= 70
),

top_decile_metrics AS (
    -- Part 2: Calculate metrics for the top decile of scores
    SELECT
        AVG(los) AS mean_icu_los_days_top_decile,
        AVG(hospital_expire_flag) * 100 AS hospital_mortality_percent_top_decile
    FROM
        ranked_cohort
    WHERE
        score_decile = 1
)

-- Final Step: Combine results from both parts into a single output
SELECT
    pc.percentile_for_score_70,
    tdm.mean_icu_los_days_top_decile,
    tdm.hospital_mortality_percent_top_decile
FROM
    percentile_calculation AS pc,
    top_decile_metrics AS tdm;