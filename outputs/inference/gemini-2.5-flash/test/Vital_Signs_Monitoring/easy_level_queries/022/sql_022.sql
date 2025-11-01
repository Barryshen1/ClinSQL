SELECT
    AVG(max_map_per_stay.max_map_value) AS average_of_max_maps
FROM
    `physionet-data.mimiciv_3_1_hosp.patients` AS p
INNER JOIN
    `physionet-data.mimiciv_3_1_icu.icustays` AS icu
    ON p.subject_id = icu.subject_id
INNER JOIN (
    SELECT
        ce.stay_id,
        MAX(ce.valuenum) AS max_map_value
    FROM
        `physionet-data.mimiciv_3_1_icu.chartevents` AS ce
    WHERE
        ce.itemid = 220052 -- ItemID for 'Arterial Blood Pressure mean'
        AND ce.valuenum IS NOT NULL
        AND ce.valuenum > 0 -- Ensure positive values
        AND ce.valuenum BETWEEN 10 AND 200 -- Physiologically plausible range for MAP
    GROUP BY
        ce.stay_id
) AS max_map_per_stay
ON icu.stay_id = max_map_per_stay.stay_id
WHERE
    p.gender = 'M'
    AND p.anchor_age BETWEEN 48 AND 58;