SELECT
    PERCENTILE_CONT(MeanRatesPerStay.mean_respiratory_rate, 0.75) OVER() AS p75_mean_respiratory_rate
FROM (
    SELECT
        icu.stay_id,
        AVG(ce.valuenum) AS mean_respiratory_rate
    FROM
        `physionet-data.mimiciv_3_1_hosp.patients` AS p
    INNER JOIN
        `physionet-data.mimiciv_3_1_icu.icustays` AS icu
        ON p.subject_id = icu.subject_id
    INNER JOIN
        `physionet-data.mimiciv_3_1_icu.chartevents` AS ce
        ON icu.stay_id = ce.stay_id
    WHERE
        p.gender = 'F'
        AND p.anchor_age BETWEEN 39 AND 49
        AND ce.itemid = 220210 -- Itemid for 'Respiratory Rate'
        AND ce.valuenum IS NOT NULL
        AND ce.valuenum > 0
        AND ce.valuenum <= 70 -- Filter out extreme values (e.g., > 70 breaths/min is very rare/artifact)
    GROUP BY
        icu.stay_id
) AS MeanRatesPerStay;