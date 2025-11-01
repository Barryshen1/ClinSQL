WITH icu_population AS (
    -- Step 1: Identify the target patient population (female, age 38-48, ICU stays)
    SELECT
        p.subject_id,
        p.gender,
        p.anchor_age,
        ie.hadm_id,
        ie.stay_id,
        ie.intime
    FROM `physionet-data.mimiciv_3_1_hosp.patients` p
    INNER JOIN `physionet-data.mimiciv_3_1_icu.icustays` ie
        ON p.subject_id = ie.subject_id
    WHERE
        p.gender = 'F'
        AND p.anchor_age BETWEEN 38 AND 48
),
avg_sbp_per_stay AS (
    -- Step 2: Calculate average SBP for each eligible ICU stay within the first 24 hours
    SELECT
        ip.stay_id,
        AVG(ce.valuenum) AS avg_sbp_24hr
    FROM icu_population ip
    INNER JOIN `physionet-data.mimiciv_3_1_icu.chartevents` ce
        ON ip.subject_id = ce.subject_id
        AND ip.hadm_id = ce.hadm_id
        AND ip.stay_id = ce.stay_id
    WHERE
        ce.itemid IN (220050, 220179) -- Common itemids for Systolic BP (Arterial and Non-Invasive)
        AND ce.valuenum IS NOT NULL
        AND ce.valuenum BETWEEN 10 AND 300 -- Filter for clinically plausible SBP values
        AND ce.charttime >= ip.intime
        AND ce.charttime < TIMESTAMP_ADD(ip.intime, INTERVAL 24 HOUR) -- First 24 hours of ICU stay
    GROUP BY ip.stay_id
    HAVING COUNT(ce.valuenum) > 0 -- Ensure at least one SBP measurement exists in the window
),
percentile_distribution AS (
    -- Step 3: Calculate the cumulative distribution (percentile value from 0 to 1)
    -- for each average SBP value across the target population.
    SELECT
        avg_sbp_24hr,
        CUME_DIST() OVER (ORDER BY avg_sbp_24hr) AS percentile_value
    FROM avg_sbp_per_stay
)
-- Step 4: Find the percentile of a per-stay average SBP of 120 mmHg
-- This retrieves the highest percentile_value for any stay whose average SBP is <= 120 mmHg.
-- If no such values exist (i.e., all avg_sbp are > 120), it will return 0.
SELECT
    COALESCE(MAX(pd.percentile_value), 0) * 100 AS percentile_for_120_mmHg
FROM percentile_distribution AS pd
WHERE pd.avg_sbp_24hr <= 120;