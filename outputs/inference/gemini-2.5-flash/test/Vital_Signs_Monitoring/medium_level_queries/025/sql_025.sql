WITH PatientDemographics AS (
    -- Select male patients aged 82-92 and their ICU stay details
    SELECT
        p.subject_id,
        p.anchor_age,
        ic.hadm_id,
        ic.stay_id,
        ic.intime
    FROM
        `physionet-data.mimiciv_3_1_hosp.patients` p
    JOIN
        `physionet-data.mimiciv_3_1_icu.icustays` ic
        ON p.subject_id = ic.subject_id
    WHERE
        p.gender = 'M'
        AND p.anchor_age BETWEEN 82 AND 92
),
TempMeasurementsFirst24H AS (
    -- Get temperature-C measurements within the first 24 hours of each relevant ICU stay
    SELECT
        pd.stay_id,
        ce.valuenum AS temp_c_reading
    FROM
        PatientDemographics pd
    JOIN
        `physionet-data.mimiciv_3_1_icu.chartevents` ce
        ON pd.subject_id = ce.subject_id
        AND pd.hadm_id = ce.hadm_id
        AND pd.stay_id = ce.stay_id
    WHERE
        ce.itemid = 223762 -- ItemID for 'Temperature C'
        AND ce.valuenum IS NOT NULL -- Ensure numeric value exists
        AND ce.valuenum > 0 -- Filter out erroneous zero values
        AND ce.charttime BETWEEN pd.intime AND TIMESTAMP_ADD(pd.intime, INTERVAL 24 HOUR)
),
AvgStayTemps AS (
    -- Calculate the average temperature for each ICU stay
    SELECT
        stay_id,
        AVG(temp_c_reading) AS avg_temp_c
    FROM
        TempMeasurementsFirst24H
    GROUP BY
        stay_id
    HAVING
        -- Ensure that there was at least one valid temp reading to average
        AVG(temp_c_reading) IS NOT NULL
)
-- Calculate the percentile of 37.5°C among these average temperatures
SELECT
    (COUNTIF(ast.avg_temp_c <= 37.5) * 100.0 / COUNT(ast.avg_temp_c)) AS percentile_of_37_5_c
FROM
    AvgStayTemps ast;