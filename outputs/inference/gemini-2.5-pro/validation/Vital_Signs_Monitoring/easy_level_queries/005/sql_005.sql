SELECT
    APPROX_QUANTILES(ce.valuenum, 100)[OFFSET(75)] AS sbp_75th_percentile
FROM
    `physionet-data.mimiciv_3_1_hosp.patients` AS p
INNER JOIN
    `physionet-data.mimiciv_3_1_icu.chartevents` AS ce
    ON p.subject_id = ce.subject_id
WHERE
    -- 1. Filter for the patient cohort: female, aged 59-69
    p.gender = 'F'
    AND p.anchor_age BETWEEN 59 AND 69

    -- 2. Filter for systolic blood pressure itemids
    -- 220179: Non Invasive Blood Pressure systolic
    -- 220050: Arterial Blood Pressure systolic
    AND ce.itemid IN (220179, 220050)

    -- 3. Filter for plausible clinical values to exclude errors
    AND ce.valuenum IS NOT NULL
    AND ce.valuenum > 0
    AND ce.valuenum < 400;