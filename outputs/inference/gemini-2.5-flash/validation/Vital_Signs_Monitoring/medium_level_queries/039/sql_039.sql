WITH icustay_cohort AS (
    -- Step 1: Identify the target patient cohort (male ICU patients aged 83-93)
    SELECT
        p.subject_id,
        ad.hadm_id,
        ic.stay_id,
        ic.intime
    FROM
        `physionet-data.mimiciv_3_1_icu.icustays` ic
    INNER JOIN
        `physionet-data.mimiciv_3_1_hosp.admissions` ad
        ON ic.hadm_id = ad.hadm_id
    INNER JOIN
        `physionet-data.mimiciv_3_1_hosp.patients` p
        ON ic.subject_id = p.subject_id
    WHERE
        p.gender = 'M'
        -- Filter by age range at admission
        AND p.anchor_age BETWEEN 83 AND 93
),
map_measurements_first_48hr AS (
    -- Step 2 & 3: Extract MAP measurements within the first 48 hours
    SELECT
        coh.stay_id,
        ce.valuenum
    FROM
        icustay_cohort coh
    INNER JOIN
        `physionet-data.mimiciv_3_1_icu.chartevents` ce
        ON coh.subject_id = ce.subject_id
        AND coh.hadm_id = ce.hadm_id
        AND coh.stay_id = ce.stay_id
    WHERE
        ce.itemid = 220052 -- itemid for 'Arterial Blood Pressure mean'
        AND ce.valuenum IS NOT NULL -- Ensure numeric value exists
        AND ce.valuenum > 10 AND ce.valuenum < 200 -- Filter for physiologically plausible values
        -- Filter for measurements within the first 48 hours of ICU stay
        AND ce.charttime >= coh.intime
        AND ce.charttime <= DATETIME_ADD(coh.intime, INTERVAL 48 HOUR)
),
per_stay_avg_map AS (
    -- Step 4: Calculate the per-stay average MAP and apply measurement count constraint
    SELECT
        stay_id,
        AVG(valuenum) AS avg_map_48hr,
        COUNT(valuenum) AS num_measurements
    FROM
        map_measurements_first_48hr
    GROUP BY
        stay_id
    HAVING
        num_measurements >= 3 -- At least 3 measurements required
)
-- Step 5: Determine the percentile for the declared map_value_of_interest
SELECT
    -- Calculate the percentile: (Count of stays with avg_map <= target_value) / (Total count of stays) * 100
    CAST(SUM(CASE WHEN avg_map_48hr <= 60 THEN 1 ELSE 0 END) * 100.0 / COUNT(stay_id) AS BIGNUMERIC)
    AS percentile_for_60_mmhg
FROM
    per_stay_avg_map;