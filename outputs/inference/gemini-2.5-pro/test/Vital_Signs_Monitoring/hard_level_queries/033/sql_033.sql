WITH
-- CTE 1: Define the patient cohort of female ICU patients aged 51-61.
cohort_stays AS (
    SELECT
        p.subject_id,
        icu.hadm_id,
        icu.stay_id,
        icu.intime,
        icu.los
    FROM
        `physionet-data.mimiciv_3_1_hosp.patients` AS p
    INNER JOIN
        `physionet-data.mimiciv_3_1_icu.icustays` AS icu
        ON p.subject_id = icu.subject_id
    WHERE
        p.gender = 'F'
        -- Calculate age at the time of ICU admission and filter
        AND (DATETIME_DIFF(icu.intime, DATETIME(p.anchor_year, 1, 1, 0, 0, 0), YEAR) + p.anchor_age) BETWEEN 51 AND 61
),

-- CTE 2: Gather all relevant instability events (vitals and vasopressors) in the first 48h.
instability_events AS (
    -- Subquery for vital signs from chartevents
    SELECT
        cs.stay_id,
        ce.itemid,
        ce.valuenum
    FROM cohort_stays AS cs
    INNER JOIN `physionet-data.mimiciv_3_1_icu.chartevents` AS ce
        ON cs.stay_id = ce.stay_id
    WHERE
        ce.charttime BETWEEN cs.intime AND DATETIME_ADD(cs.intime, INTERVAL 48 HOUR)
        AND ce.itemid IN (
            220045, -- Heart Rate
            220179, -- Non Invasive Blood Pressure systolic
            220050, -- Arterial Blood Pressure systolic
            220181, -- Non Invasive Blood Pressure mean
            220052, -- Arterial Blood Pressure mean
            220277, -- O2 saturation pulseoxymetry
            220210, -- Respiratory Rate
            223762, -- Temperature Celsius
            223761  -- Temperature Fahrenheit
        )
        AND ce.valuenum IS NOT NULL AND ce.valuenum > 0

    UNION ALL

    -- Subquery for vasopressor administrations from inputevents
    SELECT
        cs.stay_id,
        ie.itemid,
        1 AS valuenum -- Use 1 to flag an event
    FROM cohort_stays AS cs
    INNER JOIN `physionet-data.mimiciv_3_1_icu.inputevents` AS ie
        ON cs.stay_id = ie.stay_id
    WHERE
        ie.starttime BETWEEN cs.intime AND DATETIME_ADD(cs.intime, INTERVAL 48 HOUR)
        AND ie.itemid IN (
            221906, -- Norepinephrine
            221289, -- Epinephrine
            222315, -- Vasopressin
            221662, -- Dopamine
            221749, -- Phenylephrine
            221653  -- Dobutamine
        )
        AND ie.amount > 0 -- Ensure the drug was administered
),

-- CTE 3: Calculate the instability score for each stay_id based on the events.
instability_scores_per_stay AS (
    SELECT
        stay_id,
        -- Sum points for each unstable vital sign measurement
        SUM(
            CASE
                WHEN itemid = 220045 AND (valuenum < 50 OR valuenum > 120) THEN 1  -- Heart Rate
                WHEN itemid IN (220179, 220050) AND valuenum < 90 THEN 1  -- Systolic BP
                WHEN itemid IN (220181, 220052) AND valuenum < 65 THEN 1  -- Mean Arterial Pressure
                WHEN itemid = 220277 AND valuenum < 90 THEN 1  -- SpO2
                WHEN itemid = 220210 AND (valuenum < 8 OR valuenum > 25) THEN 1  -- Respiratory Rate
                WHEN itemid = 223762 AND (valuenum < 36 OR valuenum > 38.5) THEN 1  -- Temperature C
                WHEN itemid = 223761 AND (((valuenum - 32) * 5/9) < 36 OR ((valuenum - 32) * 5/9) > 38.5) THEN 1  -- Temperature F
                ELSE 0
            END
        ) AS vitals_instability_points,
        -- Count if any vasopressor was used
        COUNTIF(itemid IN (221906, 221289, 222315, 221662, 221749, 221653)) AS vaso_events_count
    FROM instability_events
    GROUP BY stay_id
),

-- CTE 4: Combine cohort data with scores and outcomes (mortality).
-- Use a LEFT JOIN to include patients with a score of 0.
final_scores AS (
    SELECT
        cs.stay_id,
        cs.los,
        adm.hospital_expire_flag,
        -- The final score is the sum of vital points plus a 20-point penalty for any vasopressor use.
        COALESCE(isps.vitals_instability_points, 0)
        + IF(COALESCE(isps.vaso_events_count, 0) > 0, 20, 0) AS instability_score
    FROM
        cohort_stays AS cs
    LEFT JOIN
        instability_scores_per_stay AS isps ON cs.stay_id = isps.stay_id
    INNER JOIN
        `physionet-data.mimiciv_3_1_hosp.admissions` AS adm ON cs.hadm_id = adm.hadm_id
),

-- CTE 5: Rank patients into deciles based on their instability score.
ranked_cohort AS (
    SELECT
        *,
        NTILE(10) OVER (ORDER BY instability_score DESC) as score_decile
    FROM
        final_scores
)

-- Final result set, combining the two parts of the question.
-- Part 1: Calculate the percentile for an instability score of 80.
SELECT
    'Percentile of instability score 80' AS metric,
    ROUND((COUNTIF(instability_score <= 80) * 100.0) / COUNT(*), 1) AS value
FROM
    final_scores

UNION ALL

-- Part 2: Report outcomes for the most unstable decile.
SELECT
    'Average ICU LOS (days) for most unstable decile' AS metric,
    ROUND(AVG(los), 1) AS value
FROM
    ranked_cohort
WHERE
    score_decile = 1

UNION ALL

SELECT
    'Hospital mortality (%) for most unstable decile' AS metric,
    ROUND(AVG(hospital_expire_flag) * 100, 1) AS value
FROM
    ranked_cohort
WHERE
    score_decile = 1;