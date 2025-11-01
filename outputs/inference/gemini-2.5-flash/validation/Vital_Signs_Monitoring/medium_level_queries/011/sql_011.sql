WITH filtered_stays AS (
    SELECT
        ie.subject_id,
        ie.stay_id,
        ie.intime
    FROM
        `physionet-data.mimiciv_3_1_icu.icustays` ie
    JOIN
        `physionet-data.mimiciv_3_1_hosp.patients` p
        ON ie.subject_id = p.subject_id
    WHERE
        p.gender = 'M'
        AND p.anchor_age BETWEEN 54 AND 64
),
-- Step 2: Calculate the average respiratory rate for each stay within the first 48 hours
per_stay_avg_rr AS (
    SELECT
        fs.stay_id,
        AVG(ce.valuenum) AS avg_rr_48h
    FROM
        `physionet-data.mimiciv_3_1_icu.chartevents` ce
    JOIN
        filtered_stays fs
        ON ce.stay_id = fs.stay_id
    WHERE
        ce.itemid = 220210 -- itemid for 'Respiratory Rate' (checked in d_items)
        AND ce.charttime BETWEEN fs.intime AND DATETIME_ADD(fs.intime, INTERVAL 48 HOUR)
        AND ce.valuenum IS NOT NULL
        AND ce.valuenum > 0
        AND ce.valuenum < 100 -- Filter for physiologically plausible values
    GROUP BY
        fs.stay_id
    HAVING
        -- Ensure there was at least one valid RR measurement to calculate an average
        COUNT(ce.valuenum) > 0
),
-- Step 3: Categorize each stay's average RR
categorized_rr AS (
    SELECT
        stay_id,
        avg_rr_48h,
        CASE
            WHEN avg_rr_48h < 12 THEN '<12'
            WHEN avg_rr_48h BETWEEN 12 AND 20 THEN '12-20'
            WHEN avg_rr_48h BETWEEN 21 AND 29 THEN '21-29'
            WHEN avg_rr_48h >= 30 THEN '>=30'
            ELSE 'Unknown' -- This case should be rare given prior filters, but good practice
        END AS rr_category
    FROM
        per_stay_avg_rr
)
-- Step 4: Calculate aggregate statistics (n, mean, median, IQR) per category
SELECT
    rr_category,
    COUNT(stay_id) AS n,
    ROUND(AVG(avg_rr_48h), 2) AS mean_rr,
    -- APPROX_QUANTILES for median (2nd quantile) and IQR (1st and 3rd quartiles)
    ROUND(APPROX_QUANTILES(avg_rr_48h, 2)[OFFSET(1)], 2) AS median_rr, -- Median
    ROUND(APPROX_QUANTILES(avg_rr_48h, 4)[OFFSET(1)], 2) AS q1_rr, -- 25th percentile
    ROUND(APPROX_QUANTILES(avg_rr_48h, 4)[OFFSET(3)], 2) AS q3_rr -- 75th percentile
FROM
    categorized_rr
GROUP BY
    rr_category
ORDER BY
    CASE rr_category
        WHEN '<12' THEN 1
        WHEN '12-20' THEN 2
        WHEN '21-29' THEN 3
        WHEN '>=30' THEN 4
        ELSE 5
    END;