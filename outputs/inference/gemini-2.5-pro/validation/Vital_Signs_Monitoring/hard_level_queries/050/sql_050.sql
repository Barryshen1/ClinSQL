WITH
-- 1. Identify ICU stays with Renal Replacement Therapy (RRT)
rrt_stays AS (
    SELECT DISTINCT stay_id
    FROM `physionet-data.mimiciv_3_1_icu.procedureevents`
    WHERE itemid IN (
        225802, -- Dialysis - CRRT
        225803, -- Dialysis - CVVHD
        225805, -- Dialysis - SCUF
        224144, -- HD/CAPD/CRRT
        224145  -- Hemodialysis
    )
    UNION DISTINCT
    SELECT DISTINCT stay_id
    FROM `physionet-data.mimiciv_3_1_icu.outputevents`
    WHERE itemid IN (
        226499, -- Dialysate Output
        227494  -- Dialysate Rate
    )
),

-- 2. Define the base cohort: Female ICU patients, 52-62 years old, on RRT
cohort AS (
    SELECT
        i.subject_id,
        i.hadm_id,
        i.stay_id,
        i.intime,
        i.los
    FROM `physionet-data.mimiciv_3_1_icu.icustays` AS i
    INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` AS p
        ON i.subject_id = p.subject_id
    INNER JOIN rrt_stays AS rrt
        ON i.stay_id = rrt.stay_id
    WHERE
        p.gender = 'F'
        AND (p.anchor_age + EXTRACT(YEAR FROM i.intime) - p.anchor_year) BETWEEN 52 AND 62
),

-- 3. Identify and flag unstable vital signs in the first 72 hours for the cohort
unstable_vitals AS (
    SELECT
        c.stay_id,
        -- Count 1 for each measurement that falls into an unstable range
        CASE
            -- Heart Rate (bpm): < 50 or > 130
            WHEN ce.itemid = 220045 AND (ce.valuenum < 50 OR ce.valuenum > 130) THEN 1
            -- Systolic BP (mmHg): < 90
            WHEN ce.itemid IN (220179, 220050) AND ce.valuenum < 90 THEN 1
            -- Mean Arterial Pressure (mmHg): < 65
            WHEN ce.itemid IN (220181, 220052) AND ce.valuenum < 65 THEN 1
            -- SpO2 (%): < 90
            WHEN ce.itemid = 220277 AND ce.valuenum < 90 THEN 1
            -- Respiratory Rate (insp/min): < 8 or > 25
            WHEN ce.itemid = 220210 AND (ce.valuenum < 8 OR ce.valuenum > 25) THEN 1
            ELSE 0
        END AS is_unstable
    FROM `physionet-data.mimiciv_3_1_icu.chartevents` AS ce
    INNER JOIN cohort AS c
        ON ce.stay_id = c.stay_id
    WHERE
        ce.charttime BETWEEN c.intime AND DATETIME_ADD(c.intime, INTERVAL 72 HOUR)
        AND ce.itemid IN (
            220045, -- Heart Rate
            220179, -- Non Invasive Blood Pressure systolic
            220050, -- Arterial Blood Pressure systolic
            220181, -- Non Invasive Blood Pressure mean
            220052, -- Arterial Blood Pressure mean
            220277, -- O2 saturation pulseoxymetry
            220210  -- Respiratory Rate
        ) AND ce.valuenum IS NOT NULL
),

-- 4. Calculate the total instability score for each patient
patient_scores AS (
    SELECT
        stay_id,
        SUM(is_unstable) AS instability_score
    FROM unstable_vitals
    GROUP BY stay_id
),

-- 5. Combine scores with outcomes for all cohort patients and calculate percentile rank
cohort_scores_and_outcomes AS (
    SELECT
        c.stay_id,
        c.los,
        a.hospital_expire_flag,
        COALESCE(ps.instability_score, 0) AS instability_score,
        PERCENT_RANK() OVER (ORDER BY COALESCE(ps.instability_score, 0)) AS score_percentile_rank
    FROM cohort AS c
    LEFT JOIN patient_scores ps
        ON c.stay_id = ps.stay_id
    INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a
        ON c.hadm_id = a.hadm_id
)

-- 6. Final calculation of the requested metrics
SELECT
    (SELECT
        (COUNTIF(instability_score < 65) * 100.0) / COUNT(instability_score)
     FROM cohort_scores_and_outcomes
    ) AS percentile_of_score_65,
    AVG(CASE WHEN score_percentile_rank >= 0.9 THEN los END) AS top_decile_mean_los_days,
    AVG(CASE WHEN score_percentile_rank >= 0.9 THEN hospital_expire_flag END) * 100 AS top_decile_mortality_percent
FROM cohort_scores_and_outcomes;