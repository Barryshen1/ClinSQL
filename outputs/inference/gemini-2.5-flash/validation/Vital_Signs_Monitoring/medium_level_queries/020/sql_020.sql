SELECT
    ROUND(PERCENT_RANK() OVER (ORDER BY mean_map_value) * 100, 2) AS percentile_of_85_mmhg
FROM (
    -- Subquery to calculate the 48-hour mean MAP for each eligible ICU stay
    SELECT
        AVG(ce.valuenum) AS mean_map_value
    FROM
        `physionet-data.mimiciv_3_1_icu.icustays` icu
    INNER JOIN
        `physionet-data.mimiciv_3_1_hosp.patients` p
        ON icu.subject_id = p.subject_id
    INNER JOIN
        `physionet-data.mimiciv_3_1_icu.chartevents` ce
        ON icu.subject_id = ce.subject_id AND icu.stay_id = ce.stay_id
    WHERE
        p.gender = 'F'
        -- Calculate age at ICU admission
        AND (p.anchor_age + (EXTRACT(YEAR FROM icu.intime) - p.anchor_year)) BETWEEN 58 AND 68
        -- Filter for common MAP itemids
        AND ce.itemid IN (220052, 220181, 224322, 225309) -- Arterial Blood Pressure mean, Non Invasive Blood Pressure mean, NBP mean, ART Blood Pressure Mean
        -- Filter for measurements within the first 48 hours of ICU stay
        AND ce.charttime BETWEEN icu.intime AND DATETIME_ADD(icu.intime, INTERVAL 48 HOUR)
        -- Filter for plausible numeric MAP values
        AND ce.valuenum IS NOT NULL
        AND ce.valuenum > 0
        AND ce.valuenum < 250
    GROUP BY
        icu.stay_id
    HAVING
        COUNT(ce.valuenum) > 0 -- Ensure there's at least one valid MAP measurement for the stay
    
    UNION ALL
    
    -- Add a dummy row for the target MAP value (85 mmHg)
    SELECT
        85.0 AS mean_map_value
)
WHERE
    mean_map_value = 85.0 -- Select only the percentile of our target value
ORDER BY
    mean_map_value -- Order by to ensure deterministic result in case of multiple 85.0 values
LIMIT 1;