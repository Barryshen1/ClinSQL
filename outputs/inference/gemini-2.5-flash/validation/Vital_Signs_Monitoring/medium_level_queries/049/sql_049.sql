WITH target_icu_stays AS (
    -- Step 1: Identify all ICU stays for female patients aged 38-48
    SELECT
        ie.subject_id,
        ie.hadm_id,
        ie.stay_id,
        ie.intime
    FROM
        `physionet-data.mimiciv_3_1_icu.icustays` AS ie
    INNER JOIN
        `physionet-data.mimiciv_3_1_hosp.patients` AS p
        ON ie.subject_id = p.subject_id
    WHERE
        p.gender = 'F'
        AND p.anchor_age BETWEEN 38 AND 48 -- Inclusive age range
),
sbp_measurements AS (
    -- Step 2: Get all relevant SBP measurements within the first 48 hours of the ICU stay
    SELECT
        tis.stay_id,
        ce.valuenum AS sbp_value
    FROM
        target_icu_stays AS tis
    INNER JOIN
        `physionet-data.mimiciv_3_1_icu.chartevents` AS ce
        ON tis.stay_id = ce.stay_id
    WHERE
        -- Itemids for Systolic Blood Pressure (Arterial and Non-invasive)
        ce.itemid IN (220050, 220179)
        -- Ensure SBP value is recorded and within a physiologically reasonable range
        AND ce.valuenum IS NOT NULL
        AND ce.valuenum > 20 AND ce.valuenum < 300
        -- Filter for measurements within the first 48 hours of ICU admission
        AND ce.charttime BETWEEN tis.intime AND DATETIME_ADD(tis.intime, INTERVAL 48 HOUR)
),
per_stay_avg_sbp AS (
    -- Step 3: Calculate the average SBP for each ICU stay in the target population
    SELECT
        stay_id,
        AVG(sbp_value) AS avg_sbp_48hr
    FROM
        sbp_measurements
    GROUP BY
        stay_id
    HAVING
        -- Ensure there was at least one valid SBP measurement for the stay
        AVG(sbp_value) IS NOT NULL
)
-- Step 4: Calculate the percentile of 130 mmHg within the distribution of per-stay average SBPs
SELECT
    (CAST(SUM(CASE WHEN avg_sbp_48hr < 130 THEN 1 ELSE 0 END) AS BIGNUMERIC) +
     CAST(SUM(CASE WHEN avg_sbp_48hr = 130 THEN 1 ELSE 0 END) AS BIGNUMERIC) * 0.5)
    / COUNT(avg_sbp_48hr) * 100 AS percentile_of_130_mmHg
FROM
    per_stay_avg_sbp;