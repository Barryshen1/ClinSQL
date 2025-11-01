SELECT
    -- Calculate the percentile rank of the specific value 36.0°C within the distribution of average temperatures.
    -- The formula for percentile rank (P) for a value X is:
    -- P = (count of values < X + 0.5 * count of values = X) / total count of values
    -- Casting to BIGNUMERIC for intermediate sums and the final division maintains precision for the fractional result.
    (
        CAST(SUM(CASE WHEN sat.avg_temp_c < 36.0 THEN 1 ELSE 0 END) AS BIGNUMERIC) +
        CAST(SUM(CASE WHEN sat.avg_temp_c = 36.0 THEN 0.5 ELSE 0 END) AS BIGNUMERIC)
    )
    /
    CAST(COUNT(sat.avg_temp_c) AS BIGNUMERIC) AS percentile_rank_of_36_0_c
FROM
    (
        SELECT
            tp.stay_id,
            -- Calculate the average temperature in Celsius for each ICU stay.
            -- itemid 220210 corresponds to 'Temperature C' in the d_items dictionary.
            -- Filter `valuenum` for physiologically plausible ranges (20-45°C) to exclude erroneous readings,
            -- and ensure it's not zero (which is likely a sensor error for body temperature).
            AVG(CASE WHEN ce.valuenum BETWEEN 20 AND 45 AND ce.valuenum != 0 THEN ce.valuenum ELSE NULL END) AS avg_temp_c
        FROM
            -- First, identify the target population: Male ICU patients aged 85-95.
            (
                SELECT
                    p.subject_id,
                    ic.stay_id
                FROM
                    `physionet-data.mimiciv_3_1_hosp.patients` p -- Corrected dataset path
                INNER JOIN
                    `physionet-data.mimiciv_3_1_icu.icustays` ic -- Corrected dataset path
                    ON p.subject_id = ic.subject_id
                WHERE
                    p.gender = 'M'
                    AND p.anchor_age BETWEEN 85 AND 95
            ) AS tp
        INNER JOIN
            `physionet-data.mimiciv_3_1_icu.chartevents` ce -- Corrected dataset path
            ON tp.subject_id = ce.subject_id
            AND tp.stay_id = ce.stay_id
        WHERE
            ce.itemid = 220210 -- Itemid for 'Temperature C'
            AND ce.valuenum IS NOT NULL -- Ensure a numeric value exists
            AND ce.warning = 0 -- Exclude records flagged as warnings
        GROUP BY
            tp.stay_id
        HAVING
            -- Ensure that at least one valid temperature measurement contributed to the average for the stay
            AVG(CASE WHEN ce.valuenum BETWEEN 20 AND 45 AND ce.valuenum != 0 THEN ce.valuenum ELSE NULL END) IS NOT NULL
    ) AS sat;