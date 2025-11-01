WITH PatientICUStays AS (
    -- Select eligible male ICU patients aged 81-91
    SELECT
        p.subject_id,
        p.gender,
        p.anchor_age,
        icu.stay_id,
        icu.intime
    FROM
        `physionet-data.mimiciv_3_1_hosp.patients` p
    INNER JOIN
        `physionet-data.mimiciv_3_1_icu.icustays` icu
        ON p.subject_id = icu.subject_id
    WHERE
        p.gender = 'M'
        AND p.anchor_age BETWEEN 81 AND 91
),
SBP_Measurements AS (
    -- Extract systolic blood pressure measurements for the eligible patients
    -- within the first 48 hours of their ICU stay
    SELECT
        pis.stay_id,
        ce.valuenum AS sbp_value
    FROM
        PatientICUStays pis
    INNER JOIN
        `physionet-data.mimiciv_3_1_icu.chartevents` ce
        ON pis.stay_id = ce.stay_id
    WHERE
        -- ItemIDs for Systolic Blood Pressure (Arterial and Non Invasive)
        ce.itemid IN (220050, 220179)
        -- Filter to the first 48 hours of the ICU stay
        AND ce.charttime BETWEEN pis.intime AND DATETIME_ADD(pis.intime, INTERVAL 48 HOUR)
        -- Ensure valid numeric SBP values
        AND ce.valuenum IS NOT NULL
        AND ce.valuenum > 0
        AND ce.valuenum < 300 -- Exclude implausibly high values
),
AverageSBP_PerStay AS (
    -- Calculate the average SBP for each ICU stay
    SELECT
        stay_id,
        AVG(sbp_value) AS avg_sbp
    FROM
        SBP_Measurements
    GROUP BY
        stay_id
    HAVING
        COUNT(sbp_value) > 0 -- Ensure at least one valid SBP measurement for the average
),
PercentileCalculation AS (
    -- Count total stays and stays with average SBP <= 150 mmHg
    SELECT
        -- Using COALESCE for robustness if no data is found, though COUNT() handles this gracefully
        COUNT(avg_sbp) AS total_stays,
        COUNT(CASE WHEN avg_sbp <= 150 THEN 1 END) AS stays_le_150
    FROM
        AverageSBP_PerStay
)
-- Calculate the percentile
SELECT
    (CAST(pc.stays_le_150 AS FLOAT64) / pc.total_stays) * 100 AS percentile_of_150_mmHg
FROM
    PercentileCalculation pc;