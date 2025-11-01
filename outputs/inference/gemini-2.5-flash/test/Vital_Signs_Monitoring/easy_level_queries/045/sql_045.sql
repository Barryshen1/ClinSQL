WITH TargetICUPatients AS (
    -- Step 1 & 2: Identify male patients aged 51-61 who had an ICU stay
    SELECT
        p.subject_id,
        icu.stay_id
    FROM
        `physionet-data.mimiciv_3_1_hosp.patients` p
    JOIN
        `physionet-data.mimiciv_3_1_icu.icustays` icu
        ON p.subject_id = icu.subject_id
    WHERE
        p.gender = 'M'
        AND p.anchor_age BETWEEN 51 AND 61
),
FirstRespiratoryRate AS (
    -- Step 3, 4 & 5: Find the first recorded respiratory rate for each qualifying ICU stay
    SELECT
        tip.stay_id,
        ce.valuenum AS respiratory_rate_value,
        ROW_NUMBER() OVER (PARTITION BY tip.stay_id ORDER BY ce.charttime ASC) as rn
    FROM
        TargetICUPatients tip
    JOIN
        `physionet-data.mimiciv_3_1_icu.chartevents` ce
        ON tip.subject_id = ce.subject_id AND tip.stay_id = ce.stay_id
    WHERE
        ce.itemid = 220210 -- itemid for 'Respiratory Rate' from d_items table
        AND ce.valuenum IS NOT NULL
        AND ce.valuenum > 0 -- Ensure a valid, positive respiratory rate
)
-- Step 6: Calculate the standard deviation of these first respiratory rates
SELECT
    STDDEV(frr.respiratory_rate_value) AS sd_first_respiratory_rate
FROM
    FirstRespiratoryRate frr
WHERE
    frr.rn = 1;