WITH TargetICUStays AS (
    -- Select eligible ICU stays based on patient demographics:
    -- Male patients, aged 67-77, and their ICU admission time (intime).
    SELECT
        ie.stay_id,
        ie.intime
    FROM
        `physionet-data.mimiciv_3_1_icu.icustays` ie
    INNER JOIN
        `physionet-data.mimiciv_3_1_hosp.patients` p
        ON ie.subject_id = p.subject_id
    WHERE
        p.gender = 'M'
        AND p.anchor_age BETWEEN 67 AND 77
),
StayAvgTemperature AS (
    -- Calculate the average temperature for each eligible stay
    -- within the first 24 hours of their ICU admission.
    SELECT
        tis.stay_id,
        AVG(ce.valuenum) AS avg_temp_c
    FROM
        TargetICUStays tis
    INNER JOIN
        `physionet-data.mimiciv_3_1_icu.chartevents` ce
        ON tis.stay_id = ce.stay_id
    WHERE
        -- Filter for specific item IDs corresponding to Celsius temperature measurements.
        ce.itemid IN (
            223762, -- Temperature C (likely general temperature)
            224684  -- Temperature C (O) (likely oral temperature)
            -- Referencing d_items table for definitive itemid labels:
            -- SELECT itemid, label, unitname FROM `physionet-data.mimiciv_3_1_icu.d_items` WHERE label LIKE '%Temperature%' AND unitname = 'C'
        )
        AND ce.valuenum IS NOT NULL
        -- Ensure measurements are within a reasonable physiological range for Celsius.
        AND ce.valuenum BETWEEN 25.0 AND 45.0
        -- Filter measurements to the first 24 hours of the ICU stay.
        AND ce.charttime >= tis.intime
        AND ce.charttime <= DATETIME_ADD(tis.intime, INTERVAL 24 HOUR)
    GROUP BY
        tis.stay_id
    HAVING
        -- Only include stays that have at least one valid temperature measurement
        -- within the specified time window to calculate an average.
        COUNT(ce.valuenum) > 0
)
-- Calculate the percentile of a 36.0°C average temperature.
-- This is computed as the percentage of stays whose average temperature
-- is less than or equal to 36.0°C, out of all eligible stays.
SELECT
    SAFE_DIVIDE(
        CAST(COUNTIF(sat.avg_temp_c <= 36.0) AS BIGNUMERIC) * 100.0,
        COUNT(sat.stay_id)
    ) AS percentile_of_36_0_c
FROM
    StayAvgTemperature sat;