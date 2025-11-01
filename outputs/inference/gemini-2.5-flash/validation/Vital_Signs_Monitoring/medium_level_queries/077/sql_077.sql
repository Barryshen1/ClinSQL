WITH cohort_icu_stays AS (
    -- Step 1: Identify the target cohort of ICU stays
    SELECT
        ic.subject_id,
        ic.hadm_id,
        ic.stay_id,
        p.gender,
        p.anchor_age
    FROM
        `physionet-data.mimiciv_3_1_icu.icustays` ic
    INNER JOIN
        `physionet-data.mimiciv_3_1_hosp.patients` p
        ON ic.subject_id = p.subject_id
    WHERE
        p.gender = 'F'
        AND p.anchor_age BETWEEN 42 AND 52
),
avg_hr_per_stay AS (
    -- Step 2 & 3: Calculate the average heart rate for each eligible ICU stay
    SELECT
        cis.stay_id,
        AVG(ce.valuenum) AS avg_heart_rate
    FROM
        cohort_icu_stays cis
    INNER JOIN
        `physionet-data.mimiciv_3_1_icu.chartevents` ce
        ON cis.stay_id = ce.stay_id
    WHERE
        ce.itemid = 220045 -- Itemid for 'Heart Rate' from d_items
        AND ce.valuenum IS NOT NULL -- Ensure a numeric value exists
        AND ce.valuenum > 0        -- Heart rate must be positive
    GROUP BY
        cis.stay_id
    HAVING
        COUNT(ce.valuenum) >= 5 -- Require a minimum number of measurements for a stable average
),
all_hr_values_for_ranking AS (
    -- Step 5: Combine the calculated average heart rates with the target value (90 bpm)
    -- to calculate its percentile rank within the distribution.
    SELECT avg_heart_rate FROM avg_hr_per_stay
    UNION ALL
    SELECT 90.0 AS avg_heart_rate -- Add the target value for ranking purposes
)
SELECT
    (SELECT COUNT(ahr.stay_id) FROM avg_hr_per_stay ahr) AS cohort_size, -- Step 4: Get the cohort size
    (
        -- Step 5: Calculate the PERCENT_RANK of 90 bpm
        SELECT
            CAST(PERCENT_RANK() OVER (ORDER BY all_values.avg_heart_rate) * 100 AS BIGNUMERIC)
        FROM
            all_hr_values_for_ranking all_values
        WHERE
            all_values.avg_heart_rate = 90.0
        ORDER BY
            all_values.avg_heart_rate -- Ensures consistent result if multiple 90s (though value is constant)
        LIMIT 1 -- Select only one result for the percentile (it will be the same for all 90s)
    ) AS percentile_of_90_bpm;