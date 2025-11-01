WITH hr_first_24_hours AS (
    -- Select Heart Rate measurements for the first 24 hours of each ICU stay
    SELECT
        ie.subject_id,
        ie.hadm_id,
        ie.stay_id,
        ie.intime, -- Include intime for age calculation later
        AVG(ce.valuenum) AS avg_hr_24h
    FROM
        `physionet-data.mimiciv_3_1_icu.chartevents` ce
    INNER JOIN
        `physionet-data.mimiciv_3_1_icu.icustays` ie
        ON ce.stay_id = ie.stay_id
    WHERE
        ce.itemid = 220045 -- Itemid for Heart Rate
        AND ce.valuenum IS NOT NULL
        AND ce.valuenum > 0 AND ce.valuenum < 300 -- Filter for physiologically plausible HR values
        -- Limit to measurements within the first 24 hours of ICU stay
        AND ce.charttime BETWEEN ie.intime AND DATETIME_ADD(ie.intime, INTERVAL 24 HOUR)
    GROUP BY
        ie.subject_id, ie.hadm_id, ie.stay_id, ie.intime
    HAVING
        -- Ensure an average could be calculated for the stay and it's physiologically plausible
        AVG(ce.valuenum) IS NOT NULL
        AND AVG(ce.valuenum) > 0 AND AVG(ce.valuenum) < 300
),
filtered_cohort AS (
    -- Filter the average HR data for female ICU patients aged 67-77 at admission
    SELECT
        hr.avg_hr_24h
    FROM
        hr_first_24_hours hr
    INNER JOIN
        `physionet-data.mimiciv_3_1_hosp.patients` p
        ON hr.subject_id = p.subject_id
    WHERE
        p.gender = 'F'
        -- Calculate age at ICU admission
        AND (p.anchor_age + (EXTRACT(YEAR FROM hr.intime) - p.anchor_year)) BETWEEN 67 AND 77
),
cohort_with_target AS (
    -- Combine the filtered cohort's average HRs with the target HR (110 bpm)
    -- This allows PERCENT_RANK() to calculate where 110 falls within the distribution
    SELECT avg_hr_24h FROM filtered_cohort
    UNION ALL
    SELECT 110 AS avg_hr_24h -- Add the target value to the distribution
),
percentile_calculation AS (
    -- Calculate the PERCENT_RANK for every value in the combined set
    SELECT
        avg_hr_24h,
        PERCENT_RANK() OVER (ORDER BY avg_hr_24h) AS p_rank
    FROM cohort_with_target
)
-- Select the percentile rank specifically for the 110 bpm target value
SELECT
    -- Multiply by 100 to express as a percentage, round to 2 decimal places for readability
    ROUND(p_rank * 100, 2) AS percentile_of_110_bpm
FROM percentile_calculation
WHERE avg_hr_24h = 110
ORDER BY p_rank DESC -- In case there are multiple entries for 110 (from original data and UNION), pick one.
LIMIT 1;