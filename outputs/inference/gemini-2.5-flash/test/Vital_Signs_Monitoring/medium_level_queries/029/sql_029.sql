WITH cohort_mean_spo2 AS (
    SELECT
        ie.subject_id,
        ie.hadm_id,
        ie.stay_id,
        AVG(ce.valuenum) AS mean_spo2_24hr
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
        AND p.anchor_age BETWEEN 73 AND 83
        AND ce.itemid = 220277 -- ItemID for SpO2 percentage
        AND ce.valuenum IS NOT NULL
        AND ce.valuenum > 0
        AND ce.valuenum <= 100 -- Physiological range for SpO2 percentage
        -- Filter for the first 24 hours of the ICU stay
        AND ce.charttime BETWEEN ie.intime AND DATETIME_ADD(ie.intime, INTERVAL 24 HOUR)
    GROUP BY
        ie.subject_id,
        ie.hadm_id,
        ie.stay_id
    HAVING
        -- Ensure there is at least one valid SpO2 measurement to compute an average
        COUNT(ce.valuenum) > 0
)
SELECT
    -- Calculate the percentile of a mean SpO2 value of 92 within the defined cohort
    (COUNT(CASE WHEN cohort.mean_spo2_24hr <= 92 THEN 1 END) * 100.0 / COUNT(*)) AS percentile_for_92_spo2
FROM
    cohort_mean_spo2 AS cohort;