WITH cohort_icustays AS (
    -- Step 1: Identify all ICU stays for female patients aged 45-55
    SELECT
        p.subject_id,
        ie.hadm_id,
        ie.stay_id,
        ie.intime
    FROM
        `physionet-data.mimiciv_3_1_icu.icustays` ie
    INNER JOIN
        `physionet-data.mimiciv_3_1_hosp.patients` p
        ON ie.subject_id = p.subject_id
    WHERE
        p.gender = 'F'
        AND p.anchor_age BETWEEN 45 AND 55
),
sbp_measurements_first_24hr AS (
    -- Step 2 & 3: Extract valid SBP measurements within the first 24 hours of each relevant ICU stay
    SELECT
        cis.subject_id,
        cis.stay_id,
        ce.valuenum
    FROM
        cohort_icustays cis
    INNER JOIN
        `physionet-data.mimiciv_3_1_icu.chartevents` ce
        ON cis.stay_id = ce.stay_id
    WHERE
        ce.itemid IN (220050, 220179) -- 220050: Arterial Blood Pressure systolic, 220179: Non Invasive Blood Pressure systolic
        AND ce.valuenum IS NOT NULL -- Ensure numeric value exists
        AND ce.valuenum > 0         -- Ensure value is positive
        AND ce.valuenum BETWEEN 20 AND 300 -- Filter for physiologically plausible SBP values
        AND ce.charttime BETWEEN cis.intime AND TIMESTAMP_ADD(cis.intime, INTERVAL 24 HOUR)
),
stay_avg_sbp_24hr AS (
    -- Step 4: Calculate the average SBP for each ICU stay
    SELECT
        subject_id,
        stay_id,
        AVG(valuenum) AS average_sbp
    FROM
        sbp_measurements_first_24hr
    GROUP BY
        subject_id,
        stay_id
)
-- Step 5 & 6: Categorize SBP and count unique patients per category
SELECT
    CASE
        WHEN average_sbp < 140 THEN '<140 mmHg'
        WHEN average_sbp >= 140 AND average_sbp < 160 THEN '140-159 mmHg'
        ELSE '>=160 mmHg'
    END AS sbp_category,
    COUNT(DISTINCT subject_id) AS unique_patients_count
FROM
    stay_avg_sbp_24hr
GROUP BY
    sbp_category
ORDER BY
    CASE
        WHEN sbp_category = '<140 mmHg' THEN 1
        WHEN sbp_category = '140-159 mmHg' THEN 2
        ELSE 3
    END;