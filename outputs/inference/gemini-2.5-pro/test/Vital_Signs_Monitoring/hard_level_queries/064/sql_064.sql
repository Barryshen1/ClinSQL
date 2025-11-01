WITH icustay_cohort AS (
    -- Step 1: Define the primary cohort of male ICU patients aged 45-55
    SELECT
        p.subject_id,
        icu.hadm_id,
        icu.stay_id,
        icu.intime,
        icu.outtime,
        DATETIME_DIFF(icu.outtime, icu.intime, HOUR) / 24.0 AS icu_los_days
    FROM
        `physionet-data.mimiciv_3_1_icu.icustays` AS icu
    INNER JOIN
        `physionet-data.mimiciv_3_1_hosp.patients` AS p
        ON icu.subject_id = p.subject_id
    WHERE
        p.gender = 'M'
        AND DATETIME_DIFF(icu.intime, DATETIME(p.anchor_year, 1, 1, 0, 0, 0), YEAR) + p.anchor_age BETWEEN 45 AND 55
),

vitals_first_48h AS (
    -- Step 2: Extract relevant vital signs for the cohort in the first 48 hours
    SELECT
        c.stay_id,
        ce.charttime,
        ce.itemid,
        ce.valuenum
    FROM
        icustay_cohort AS c
    INNER JOIN
        `physionet-data.mimiciv_3_1_icu.chartevents` AS ce
        ON c.stay_id = ce.stay_id
    WHERE
        ce.charttime BETWEEN c.intime AND DATETIME_ADD(c.intime, INTERVAL 48 HOUR)
        AND ce.itemid IN (
            220045, -- Heart Rate
            220210, -- Respiratory Rate
            220277, -- O2 saturation pulseoxymetry
            220052, -- Arterial Blood Pressure mean
            225312, -- ART BP mean
            220181  -- Non Invasive Blood Pressure mean
        )
        AND ce.valuenum IS NOT NULL
),

instability_points AS (
    -- Step 3: Assign a point for each "unstable" vital sign measurement and categorize it
    SELECT
        stay_id,
        CASE
            WHEN itemid = 220045 THEN 'HR'
            WHEN itemid = 220210 THEN 'RR'
            WHEN itemid = 220277 THEN 'SpO2'
            WHEN itemid IN (220052, 225312, 220181) THEN 'MAP'
        END AS vital_category,
        CASE
            WHEN itemid = 220045 AND valuenum > 100 THEN 1                   -- Tachycardia
            WHEN itemid = 220210 AND valuenum > 22 THEN 1                    -- Tachypnea
            WHEN itemid = 220277 AND valuenum < 92 THEN 1                    -- Hypoxemia
            WHEN itemid IN (220052, 225312, 220181) AND valuenum < 65 THEN 1 -- Hypotension
            ELSE 0
        END AS point
    FROM
        vitals_first_48h
),

patient_summaries AS (
    -- Step 4: Calculate per-patient average scores and outcome flags
    SELECT
        ic.stay_id,
        ic.icu_los_days,
        adm.hospital_expire_flag,

        -- Calculate a balanced instability score by averaging the scores from each vital category
        (SELECT AVG(avg_point) FROM (
            SELECT AVG(point) AS avg_point FROM instability_points ip
            WHERE ip.stay_id = ic.stay_id GROUP BY vital_category
        )) AS avg_instability_score,

        -- Flag if patient ever had hypotension or tachycardia in the first 48h
        MAX(CASE WHEN itemid IN (220052, 225312, 220181) AND valuenum < 65 THEN 1 ELSE 0 END) AS has_hypotension,
        MAX(CASE WHEN itemid = 220045 AND valuenum > 100 THEN 1 ELSE 0 END) AS has_tachycardia

    FROM
        icustay_cohort AS ic
    LEFT JOIN
        `physionet-data.mimiciv_3_1_hosp.admissions` AS adm
        ON ic.hadm_id = adm.hadm_id
    LEFT JOIN
        vitals_first_48h AS v
        ON ic.stay_id = v.stay_id
    GROUP BY
        ic.stay_id, ic.icu_los_days, adm.hospital_expire_flag
),

cohort_with_analytics AS (
    -- Step 5: Use window functions to find the 95th percentile and assign score quartiles
    SELECT
        stay_id,
        icu_los_days,
        hospital_expire_flag,
        COALESCE(has_hypotension, 0) AS has_hypotension,
        COALESCE(has_tachycardia, 0) AS has_tachycardia,
        PERCENTILE_CONT(COALESCE(avg_instability_score, 0), 0.95) OVER() AS p95_instability_score,
        NTILE(4) OVER(ORDER BY COALESCE(avg_instability_score, 0) DESC) AS score_quartile
    FROM
        patient_summaries
)
-- Step 6: Final aggregation to compare the top quartile vs. the rest of the cohort
SELECT
    CASE
        WHEN score_quartile = 1 THEN 'Top Quartile (by Instability Score)'
        ELSE 'Quartiles 2-4'
    END AS cohort_group,
    -- The p95 score is the answer to the first part of the question
    MAX(p95_instability_score) AS cohort_wide_p95_instability_score,
    COUNT(DISTINCT stay_id) AS num_patients,
    -- The comparison metrics for the second part of the question
    AVG(has_hypotension) * 100 AS pct_with_hypotension_first_48h,
    AVG(has_tachycardia) * 100 AS pct_with_tachycardia_first_48h,
    AVG(icu_los_days) AS avg_icu_los_days,
    AVG(hospital_expire_flag) * 100 AS in_hospital_mortality_pct
FROM
    cohort_with_analytics
GROUP BY
    cohort_group
ORDER BY
    cohort_group DESC;