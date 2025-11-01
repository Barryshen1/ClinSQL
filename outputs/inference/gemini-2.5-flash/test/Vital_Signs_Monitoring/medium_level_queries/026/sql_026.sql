WITH cohort_filtered_rr AS (
    SELECT
        ie.stay_id,
        ce.valuenum
    FROM
        `physionet-data.mimiciv_3_1_icu.icustays` AS ie
    INNER JOIN
        `physionet-data.mimiciv_3_1_hosp.patients` AS p
        ON ie.subject_id = p.subject_id
    INNER JOIN
        `physionet-data.mimiciv_3_1_icu.chartevents` AS ce
        ON ie.stay_id = ce.stay_id
    WHERE
        p.gender = 'M'
        AND p.anchor_age BETWEEN 68 AND 78
        AND ce.itemid = 220210 -- Itemid for 'Respiratory Rate' from d_items
        AND ce.charttime >= ie.intime
        AND ce.charttime <= DATETIME_ADD(ie.intime, INTERVAL 48 HOUR)
        AND ce.valuenum IS NOT NULL
        AND ce.valuenum > 0 AND ce.valuenum < 70 -- Filter out physiologically impossible or erroneous values
),
-- Step 2: Calculate the average respiratory rate for each ICU stay within this cohort.
per_stay_avg_rr AS (
    SELECT
        stay_id,
        AVG(valuenum) AS avg_respiratory_rate
    FROM
        cohort_filtered_rr
    GROUP BY
        stay_id
)
-- Step 3: Calculate the percentile of a per-stay average respiratory rate of 12 breaths/min.
-- This is computed as the percentage of stays in the cohort whose average respiratory rate
-- is less than or equal to 12.
SELECT
    (COUNT(CASE WHEN avg_respiratory_rate <= 12 THEN 1 END) * 100.0) / COUNT(avg_respiratory_rate) AS percentile_of_12_bpm
FROM
    per_stay_avg_rr;