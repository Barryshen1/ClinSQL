WITH vent_patients AS (
    SELECT DISTINCT ce.subject_id, ce.hadm_id, ce.stay_id
    FROM `physionet-data.mimiciv_3_1_icu.chartevents` ce -- Corrected dataset path
    WHERE
        ce.itemid = 224696 -- itemid for 'Ventilation Mode'
        AND ce.valuenum = 1 -- Value indicating invasive ventilation is active/present (as described in the original note)
),
-- CTE 2: Select the base cohort meeting age, gender, and ventilation criteria.
patient_cohort_base AS (
    SELECT
        p.subject_id,
        adm.hadm_id,
        icu.stay_id,
        (p.anchor_age + (EXTRACT(YEAR FROM adm.admittime) - p.anchor_year)) AS age_at_admission,
        icu.intime,
        icu.los AS icu_los_days,
        adm.hospital_expire_flag
    FROM `physionet-data.mimiciv_3_1_hosp.patients` p -- Corrected dataset path
    INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` adm -- Corrected dataset path
        ON p.subject_id = adm.subject_id
    INNER JOIN `physionet-data.mimiciv_3_1_icu.icustays` icu -- Corrected dataset path
        ON adm.hadm_id = icu.hadm_id
    INNER JOIN vent_patients vp -- Filter for patients on invasive ventilation found in CTE 1
        ON icu.stay_id = vp.stay_id
    WHERE
        p.gender = 'F' -- Female patients
        AND (p.anchor_age + (EXTRACT(YEAR FROM adm.admittime) - p.anchor_year)) BETWEEN 51 AND 61 -- Age 51-61
),
-- CTE 3: Calculate the instability score for each patient in the cohort.
-- Proxy instability score: number of distinct lab itemids within the first 48 hours of ICU stay.
instability_score_calc AS (
    SELECT
        pc.stay_id,
        pc.icu_los_days,
        pc.hospital_expire_flag,
        COUNT(DISTINCT le.itemid) AS instability_score
    FROM patient_cohort_base pc
    INNER JOIN `physionet-data.mimiciv_3_1_hosp.labevents` le -- Corrected dataset path
        ON pc.subject_id = le.subject_id
        AND pc.hadm_id = le.hadm_id
    WHERE
        le.charttime >= pc.intime -- Lab event occurred after ICU admit
        AND le.charttime <= DATETIME_ADD(pc.intime, INTERVAL 48 HOUR) -- ...and within the first 48 hours
    GROUP BY
        pc.stay_id,
        pc.icu_los_days,
        pc.hospital_expire_flag
),
-- CTE 4: Rank the patients by instability score to assign deciles.
ranked_cohort AS (
    SELECT
        isc.stay_id,
        isc.instability_score,
        isc.icu_los_days,
        isc.hospital_expire_flag,
        -- Assign decile rank (1-10), with 10 being the most unstable (highest score)
        NTILE(10) OVER (ORDER BY isc.instability_score ASC) AS decile_rank
    FROM instability_score_calc isc
)
-- Part 1: Calculate the percentile for an instability score of 80.
-- This uses the empirical percentile definition: (count < X + 0.5 * count = X) / total count.
SELECT
    'Percentile for instability score of 80' AS metric_description,
    CAST(
        SAFE_DIVIDE(
            (COUNT(CASE WHEN instability_score < 80 THEN 1 END) + 0.5 * COUNT(CASE WHEN instability_score = 80 THEN 1 END)),
            COUNT(instability_score)
        ) * 100
        AS BIGNUMERIC
    ) AS value
FROM ranked_cohort

UNION ALL

-- Part 2a: Report Average ICU LOS for the most unstable decile.
SELECT
    'Avg ICU LOS for most unstable decile (days)' AS metric_description,
    CAST(AVG(icu_los_days) AS BIGNUMERIC) AS value
FROM ranked_cohort
WHERE decile_rank = 10 -- Most unstable decile (highest scores)

UNION ALL

-- Part 2b: Report Hospital Mortality for the most unstable decile.
SELECT
    'Hospital Mortality Rate for most unstable decile' AS metric_description,
    CAST(AVG(hospital_expire_flag) AS BIGNUMERIC) AS value
FROM ranked_cohort
WHERE decile_rank = 10;