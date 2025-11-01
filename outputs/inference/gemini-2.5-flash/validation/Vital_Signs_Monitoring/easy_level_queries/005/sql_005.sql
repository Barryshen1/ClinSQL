SELECT
    APPROX_QUANTILES(ce.valuenum, 100)[OFFSET(75)] AS p75_systolic_bp
FROM
    `physionet-data.mimiciv_3_1_hosp.patients` AS p
JOIN
    `physionet-data.mimiciv_3_1_icu.chartevents` AS ce
    ON p.subject_id = ce.subject_id
WHERE
    p.gender = 'F'
    AND p.anchor_age BETWEEN 59 AND 69
    AND ce.itemid IN (
        220050, -- Arterial Blood Pressure systolic
        220179  -- Non Invasive Blood Pressure Systolic
    )
    AND ce.valuenum IS NOT NULL
    AND ce.valuenum > 0   -- Filter out non-positive or erroneous values
    AND ce.valuenum < 300; -- Filter out physiologically implausible high values;