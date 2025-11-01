WITH spo2_item AS (
    SELECT
        itemid
    FROM
        `physionet-data.mimiciv_3_1_icu.d_items`
    WHERE
        label = 'O2 saturation pulseoxymetry'
),
-- Step 2: Identify the target cohort of female ICU stays aged 87-97
cohort_stays AS (
    SELECT
        p.subject_id,
        p.anchor_age,
        ie.hadm_id,
        ie.stay_id,
        ie.intime
    FROM
        `physionet-data.mimiciv_3_1_hosp.patients` p
    INNER JOIN
        `physionet-data.mimiciv_3_1_icu.icustays` ie
        ON p.subject_id = ie.subject_id
    WHERE
        p.gender = 'F'
        AND p.anchor_age BETWEEN 87 AND 97
),
-- Step 3: Get all valid SpO2 measurements within the first 24 hours for the cohort
first_24hr_spo2_measurements AS (
    SELECT
        cs.stay_id,
        ce.valuenum
    FROM
        cohort_stays cs
    INNER JOIN
        `physionet-data.mimiciv_3_1_icu.chartevents` ce
        ON cs.stay_id = ce.stay_id
    INNER JOIN
        spo2_item si
        ON ce.itemid = si.itemid
    WHERE
        ce.charttime >= cs.intime
        AND ce.charttime < DATETIME_ADD(cs.intime, INTERVAL 24 HOUR)
        AND ce.valuenum IS NOT NULL
        AND ce.valuenum BETWEEN 1 AND 100 -- Filter for physiologically plausible SpO2 values
),
-- Step 4: Calculate the average SpO2 for the first 24 hours for each relevant stay
per_stay_avg_spo2 AS (
    SELECT
        stay_id,
        AVG(valuenum) AS avg_spo2_24hr
    FROM
        first_24hr_spo2_measurements
    GROUP BY
        stay_id
    HAVING
        COUNT(valuenum) > 0 -- Ensure at least one valid measurement was taken for the average
)
-- Step 5: Calculate the percentile for a first-24-hour per-stay average SpO2 of 88%
SELECT
    -- Calculate the proportion of stays whose average SpO2 is less than or equal to 88%
    -- and multiply by 100 to express it as a percentile.
    (CAST(SUM(CASE WHEN ps.avg_spo2_24hr <= 88 THEN 1 ELSE 0 END) AS BIGNUMERIC) * 100.0) / COUNT(ps.stay_id) AS percentile_for_88_spo2
FROM
    per_stay_avg_spo2 ps;