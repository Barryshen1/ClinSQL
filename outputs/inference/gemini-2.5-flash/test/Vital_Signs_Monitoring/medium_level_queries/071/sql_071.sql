WITH TargetICUStays AS (
    -- Step 1: Identify eligible female ICU stays aged 38-48
    SELECT
        p.subject_id,
        ics.stay_id
    FROM
        `physionet-data.mimiciv_3_1_hosp.patients` AS p
    INNER JOIN
        `physionet-data.mimiciv_3_1_icu.icustays` AS ics
        ON p.subject_id = ics.subject_id
    WHERE
        p.gender = 'F'
        AND p.anchor_age BETWEEN 38 AND 48
),
SpO2Measurements AS (
    -- Step 2: Get all valid SpO2 measurements for the identified itemid
    SELECT
        ce.stay_id,
        ce.valuenum
    FROM
        `physionet-data.mimiciv_3_1_icu.chartevents` AS ce
    WHERE
        ce.itemid = 220277 -- itemid for 'O2 saturation pulseoxymetry'
        AND ce.valuenum IS NOT NULL
        AND ce.valuenum BETWEEN 0 AND 100 -- SpO2 is a percentage, usually between 0-100
),
MeanSpO2PerStay AS (
    -- Step 3: Calculate the mean SpO2 for each eligible ICU stay
    SELECT
        tis.stay_id,
        AVG(sm.valuenum) AS mean_spo2_value
    FROM
        TargetICUStays AS tis
    INNER JOIN
        SpO2Measurements AS sm
        ON tis.stay_id = sm.stay_id
    GROUP BY
        tis.stay_id
    HAVING
        COUNT(sm.valuenum) > 0 -- Ensure at least one valid SpO2 measurement for the average
)
-- Step 4: Calculate the percentile
SELECT
    -- Count stays with mean SpO2 <= 92, divide by total stays, and multiply by 100
    CAST(SUM(CASE WHEN ms.mean_spo2_value <= 92.0 THEN 1 ELSE 0 END) AS FLOAT64) / COUNT(ms.stay_id) * 100 AS percentile_at_92
FROM
    MeanSpO2PerStay AS ms;