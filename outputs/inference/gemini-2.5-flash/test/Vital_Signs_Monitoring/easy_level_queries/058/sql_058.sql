SELECT
    PERCENTILE_CONT(min_temp_f, 0.5) OVER () AS median_of_min_stay_temperature_f
FROM (
    SELECT
        icu.stay_id,
        MIN(ce.valuenum) AS min_temp_f
    FROM
        `physionet-data.mimiciv_3_1_hosp.patients` AS p
    INNER JOIN
        `physionet-data.mimiciv_3_1_icu.icustays` AS icu
        ON p.subject_id = icu.subject_id
    INNER JOIN
        `physionet-data.mimiciv_3_1_icu.chartevents` AS ce
        ON icu.subject_id = ce.subject_id
        AND icu.hadm_id = ce.hadm_id
        AND icu.stay_id = ce.stay_id
    WHERE
        p.gender = 'M'
        AND p.anchor_age BETWEEN 74 AND 84
        AND ce.itemid = 223761 -- Temperature Fahrenheit
        AND ce.valuenum IS NOT NULL
    GROUP BY
        icu.stay_id
) AS stay_min_temperatures;