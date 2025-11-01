WITH icu_population AS (
    -- Step 1: Identify all female ICU patients aged 87-97
    SELECT
        ie.subject_id,
        ie.hadm_id,
        ie.stay_id,
        ie.intime
    FROM
        `physionet-data.mimiciv_3_1_icu.icustays` ie
    INNER JOIN
        `physionet-data.mimiciv_3_1_hosp.patients` p
        ON ie.subject_id = p.subject_id
    WHERE
        p.gender = 'F'
        AND p.anchor_age BETWEEN 87 AND 97
),
first_24hr_sbp_measurements AS (
    -- Step 2: Extract Systolic BP measurements within the first 24 hours for the identified population
    SELECT
        ip.stay_id,
        ce.valuenum AS sbp_value
    FROM
        icu_population ip
    INNER JOIN
        `physionet-data.mimiciv_3_1_icu.chartevents` ce
        ON ip.subject_id = ce.subject_id
        AND ip.stay_id = ce.stay_id
    WHERE
        ce.itemid = 220050 -- Itemid for BP Systolic
        AND ce.charttime BETWEEN ip.intime AND DATETIME_ADD(ip.intime, INTERVAL 24 HOUR)
        AND ce.valuenum IS NOT NULL
        AND ce.valuenum > 20 -- Filter out physiologically implausible low SBP values
        AND ce.valuenum < 300 -- Filter out physiologically implausible high SBP values
),
avg_sbp_per_stay AS (
    -- Step 3: Calculate the average first-24-hour SBP for each ICU stay
    SELECT
        stay_id,
        AVG(sbp_value) AS avg_first_24hr_sbp
    FROM
        first_24hr_sbp_measurements
    GROUP BY
        stay_id
    HAVING
        COUNT(sbp_value) > 0 -- Ensure at least one valid SBP measurement was recorded for the average
)
-- Step 4: Calculate the percentile rank of 150 mmHg within the distribution of average SBPs
SELECT
    CAST(COUNTIF(t.avg_first_24hr_sbp <= 150.0) AS FLOAT64) / COUNT(t.avg_first_24hr_sbp) * 100 AS percentile_rank_of_150mmHg
FROM
    avg_sbp_per_stay t;