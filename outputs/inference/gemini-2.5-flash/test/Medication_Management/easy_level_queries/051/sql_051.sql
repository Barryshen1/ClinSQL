WITH PatientPrescriptions AS (
    SELECT
        -- Calculate prescription duration in days
        DATE_DIFF(CAST(p_rx.stoptime AS DATE), CAST(p_rx.starttime AS DATE), DAY) AS duration_days
    FROM
        `physionet-data.mimiciv_3_1_hosp.prescriptions` AS p_rx
    JOIN
        `physionet-data.mimiciv_3_1_hosp.patients` AS p
        ON p_rx.subject_id = p.subject_id
    WHERE
        p.gender = 'M' -- Filter for males
        AND p.anchor_age BETWEEN 86 AND 96 -- Filter for age range 86 to 96 years old
        -- Ensure drug column is cast to STRING for LOWER() and LIKE operations
        AND LOWER(CAST(p_rx.drug AS STRING)) LIKE 'digoxin%' -- Filter for Digoxin prescriptions (case-insensitive, includes variations)
        AND p_rx.starttime IS NOT NULL -- Ensure start time is recorded
        AND p_rx.stoptime IS NOT NULL -- Ensure stop time is recorded
        AND p_rx.stoptime >= p_rx.starttime -- Ensure valid duration (stop time is not before start time)
)
SELECT
    APPROX_QUANTILES(duration_days, 4)[OFFSET(1)] AS q1_duration_days, -- First quartile (25th percentile)
    APPROX_QUANTILES(duration_days, 4)[OFFSET(3)] AS q3_duration_days, -- Third quartile (75th percentile)
    (APPROX_QUANTILES(duration_days, 4)[OFFSET(3)] - APPROX_QUANTILES(duration_days, 4)[OFFSET(1)]) AS iqr_duration_days
FROM
    PatientPrescriptions;