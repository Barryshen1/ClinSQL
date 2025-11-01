WITH cohort AS (
    SELECT
        p.subject_id,
        p.gender,
        p.anchor_age,
        ie.hadm_id,
        ie.stay_id,
        ie.intime,
        ie.outtime
    FROM
        `physionet-data.mimiciv_3_1_hosp.patients` p
    JOIN
        `physionet-data.mimiciv_3_1_icu.icustays` ie
        ON p.subject_id = ie.subject_id
    WHERE
        p.gender = 'F' -- Filter for female patients
        AND p.anchor_age BETWEEN 75 AND 85 -- Filter for age between 75 and 85
),
sbp_readings AS (
    SELECT
        c.stay_id,
        ce.charttime,
        ce.valuenum AS sbp_value
    FROM
        cohort c
    JOIN
        `physionet-data.mimiciv_3_1_icu.chartevents` ce
        ON c.stay_id = ce.stay_id
    WHERE
        -- Refined itemids for Systolic Blood Pressure for MIMIC-IV
        ce.itemid IN (220050, 220179)
        AND ce.valuenum IS NOT NULL -- Ensure numeric value exists
        AND ce.valuenum > 0 AND ce.valuenum < 300 -- Filter for reasonable SBP values
        -- Filter for readings within the first 48 hours of ICU stay
        AND ce.charttime BETWEEN c.intime AND DATETIME_ADD(c.intime, INTERVAL 48 HOUR)
),
mean_48hr_sbp_per_stay AS (
    SELECT
        stay_id,
        AVG(sbp_value) AS mean_48hr_sbp
    FROM
        sbp_readings
    GROUP BY
        stay_id
    -- Removed 'HAVING AVG(sbp_value) IS NOT NULL' as it's redundant;
    -- valuenum is already checked for NOT NULL in sbp_readings CTE.
),
ranked_stays AS (
    SELECT
        stay_id,
        mean_48hr_sbp,
        -- Calculate the percentile rank (0 to 1) for each mean SBP value
        PERCENT_RANK() OVER (ORDER BY mean_48hr_sbp ASC) AS percentile_rank_val
    FROM
        mean_48hr_sbp_per_stay
)
-- Select the maximum percentile rank for mean SBP values <= 140 mmHg,
-- then multiply by 100 to get a 0-100 percentile.
SELECT
    MAX(percentile_rank_val) * 100 AS `percentile_of_140_mmHg`
FROM
    ranked_stays
WHERE
    mean_48hr_sbp <= 140;