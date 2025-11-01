WITH cohort_stays AS (
    SELECT
        p.subject_id,
        i.stay_id,
        i.intime
    FROM
        `physionet-data.mimiciv_3_1_hosp.patients` AS p
    INNER JOIN
        `physionet-data.mimiciv_3_1_icu.icustays` AS i
            ON p.subject_id = i.subject_id
    WHERE
        p.gender = 'M'
        AND p.anchor_age BETWEEN 54 AND 64
),

-- Step 2: Extract and clean respiratory rate measurements within the first 48 hours.
rr_events_first_48h AS (
    SELECT
        cs.stay_id,
        ce.valuenum
    FROM
        cohort_stays AS cs
    INNER JOIN
        `physionet-data.mimiciv_3_1_icu.chartevents` AS ce
            ON cs.stay_id = ce.stay_id
    WHERE
        ce.itemid IN (
            220210, -- Respiratory Rate
            224689, -- Respiratory Rate (spontaneous)
            224690  -- Respiratory Rate (Total)
        )
        AND ce.charttime >= cs.intime
        AND ce.charttime <= DATETIME_ADD(cs.intime, INTERVAL 48 HOUR)
        AND ce.valuenum IS NOT NULL
        AND ce.valuenum > 0      -- Exclude erroneous values
        AND ce.valuenum < 100    -- Exclude erroneous values
),

-- Step 3: Calculate the average respiratory rate per stay.
avg_rr_per_stay AS (
    SELECT
        stay_id,
        AVG(valuenum) AS avg_rr
    FROM
        rr_events_first_48h
    GROUP BY
        stay_id
),

-- Step 4: Categorize each stay based on its average respiratory rate.
categorized_stays AS (
    SELECT
        stay_id,
        avg_rr,
        CASE
            WHEN avg_rr < 12 THEN '<12'
            WHEN avg_rr >= 12 AND avg_rr <= 20 THEN '12-20'
            WHEN avg_rr >= 21 AND avg_rr <= 29 THEN '21-29'
            WHEN avg_rr >= 30 THEN '>=30'
            ELSE NULL
        END AS rr_category
    FROM
        avg_rr_per_stay
)

-- Step 5: Calculate n, mean, median, and IQR for each category.
SELECT
    rr_category,
    COUNT(stay_id) AS n,
    AVG(avg_rr) AS mean,
    APPROX_QUANTILES(avg_rr, 2)[OFFSET(1)] AS median,
    (APPROX_QUANTILES(avg_rr, 4)[OFFSET(3)] - APPROX_QUANTILES(avg_rr, 4)[OFFSET(1)]) AS iqr
FROM
    categorized_stays
WHERE
    rr_category IS NOT NULL
GROUP BY
    rr_category
ORDER BY
    CASE
        WHEN rr_category = '<12' THEN 1
        WHEN rr_category = '12-20' THEN 2
        WHEN rr_category = '21-29' THEN 3
        WHEN rr_category = '>=30' THEN 4
    END;