SELECT
    -- Calculate the 25th percentile (Q1) of duration in days
    PERCENTILE_CONT(duration_days, 0.25) OVER () AS q1_duration_days,
    -- Calculate the 75th percentile (Q3) of duration in days
    PERCENTILE_CONT(duration_days, 0.75) OVER () AS q3_duration_days,
    -- Calculate the Interquartile Range (IQR) of duration in days
    (PERCENTILE_CONT(duration_days, 0.75) OVER () - PERCENTILE_CONT(duration_days, 0.25) OVER ()) AS iqr_duration_days
FROM
    (
        SELECT
            pres.subject_id,
            pres.hadm_id,
            -- Calculate the duration of the prescription in days
            DATE_DIFF(pres.stoptime, pres.starttime, DAY) AS duration_days
        FROM
            `physionet-data.mimiciv_3_1_hosp.prescriptions` AS pres
        JOIN
            `physionet-data.mimiciv_3_1_hosp.patients` AS pat
            ON pres.subject_id = pat.subject_id
        WHERE
            -- Filter for female patients
            pat.gender = 'F'
            -- Filter for patients aged 59-69 based on anchor_age
            AND pat.anchor_age BETWEEN 59 AND 69
            -- Filter for prescriptions containing 'amiodarone' (case-insensitive)
            AND LOWER(pres.drug) LIKE '%amiodarone%'
            -- Ensure valid start and stop times for duration calculation
            AND pres.starttime IS NOT NULL
            AND pres.stoptime IS NOT NULL
            -- Ensure stoptime is not before starttime for a valid, non-negative duration
            AND pres.stoptime >= pres.starttime
    ) AS filtered_amiodarone_durations;