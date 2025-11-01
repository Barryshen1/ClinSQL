SELECT
    AVG(mean_arterial_pressure_per_stay) AS average_of_mean_map_across_stays
FROM (
    SELECT
        icu.stay_id,
        AVG(ce.valuenum) AS mean_arterial_pressure_per_stay
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
        AND p.anchor_age BETWEEN 73 AND 83
        AND (
            icu.last_careunit LIKE '%Stepdown%'
            OR icu.last_careunit LIKE '%Intermediate%'
        )
        AND ce.itemid IN (
            220052, -- Arterial Blood Pressure mean
            224687, -- Mean Artery Pressure
            224390  -- MAP (another common itemid for MAP)
        )
        AND ce.valuenum IS NOT NULL
        AND ce.valuenum > 0 -- Ensure valid positive MAP values
    GROUP BY
        icu.stay_id
) AS MeanMAPs;