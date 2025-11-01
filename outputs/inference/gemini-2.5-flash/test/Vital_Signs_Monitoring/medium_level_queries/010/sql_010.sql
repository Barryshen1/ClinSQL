WITH sbp_avg_48hr AS (
    SELECT
        ie.stay_id,
        AVG(ce.valuenum) AS avg_sbp
    FROM
        `physionet-data.mimiciv_3_1_icu.icustays` ie -- Corrected dataset name
    INNER JOIN
        `physionet-data.mimiciv_3_1_hosp.patients` p -- Corrected dataset name
        ON ie.subject_id = p.subject_id
    INNER JOIN
        `physionet-data.mimiciv_3_1_icu.chartevents` ce -- Corrected dataset name
        ON ie.stay_id = ce.stay_id
    WHERE
        p.gender = 'F'
        AND p.anchor_age BETWEEN 77 AND 87
        -- Filter for common SBP itemids
        AND ce.itemid IN (220050, 220179) -- 220050: Arterial Blood Pressure systolic, 220179: Non Invasive Blood Pressure Systolic
        AND ce.valuenum IS NOT NULL
        AND ce.valuenum BETWEEN 20 AND 300 -- Filter for physiologically plausible SBP values (e.g., 20-300 mmHg)
        AND ce.charttime >= ie.intime
        AND ce.charttime <= TIMESTAMP_ADD(ie.intime, INTERVAL 48 HOUR)
    GROUP BY
        ie.stay_id
    HAVING
        -- Ensure at least one SBP measurement contributed to the average
        COUNT(ce.valuenum) > 0
)
SELECT
    -- Calculate the percentile: (Count of averages <= 160 / Total count of averages) * 100
    CAST(SUM(CASE WHEN s.avg_sbp <= 160 THEN 1 ELSE 0 END) AS NUMERIC) * 100.0 / COUNT(s.avg_sbp) AS percentile_at_160_mmHg
FROM
    sbp_avg_48hr s;