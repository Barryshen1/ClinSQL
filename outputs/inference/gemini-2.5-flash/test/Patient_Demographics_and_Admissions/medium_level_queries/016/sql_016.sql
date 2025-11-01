WITH CohortAdmissions AS (
    SELECT
        ad.subject_id,
        ad.hadm_id,
        DATE_DIFF(ad.dischtime, ad.admittime, DAY) AS los_days,
        CASE
            WHEN ad.deathtime IS NOT NULL THEN 'Died in hospital'
            WHEN ad.discharge_location IN ('HOME', 'HOME HEALTH CARE') THEN 'Discharged Home'
            WHEN ad.discharge_location LIKE '%HOSPICE%' THEN 'Discharged to Hospice'
            ELSE 'Other Discharge' -- Include for completeness, though filtered later
        END AS discharge_status
    FROM
        `physionet-data.mimiciv_3_1_hosp.admissions` ad
    JOIN
        `physionet-data.mimiciv_3_1_hosp.patients` p
        ON ad.subject_id = p.subject_id
    WHERE
        p.gender = 'M'
        AND p.anchor_age BETWEEN 44 AND 54
        -- Filter out admissions that include any ICU stay (i.e., "general wards")
        AND NOT EXISTS (
            SELECT 1
            FROM `physionet-data.mimiciv_3_1_icu.icustays` icu
            WHERE icu.hadm_id = ad.hadm_id
        )
),
-- Step 2: Select relevant data from the cohort and filter for the specific discharge statuses requested.
CalculatedMetrics AS (
    SELECT
        discharge_status,
        los_days
    FROM
        CohortAdmissions
    WHERE
        discharge_status IN ('Discharged Home', 'Discharged to Hospice', 'Died in hospital')
)
-- Step 3: Calculate the requested approximate percentiles and the percentile rank of a 7-day stay,
--         stratified by discharge status, using aggregate functions.
SELECT
    discharge_status,
    -- LOS Percentiles using APPROX_QUANTILES (approximate)
    -- APPROX_QUANTILES(los_days, 100) returns an array of 101 elements (0-indexed quantiles 0 to 100)
    APPROX_QUANTILES(los_days, 100)[OFFSET(50)] AS los_p50_days,
    APPROX_QUANTILES(los_days, 100)[OFFSET(75)] AS los_p75_days,
    APPROX_QUANTILES(los_days, 100)[OFFSET(90)] AS los_p90_days,
    APPROX_QUANTILES(los_days, 100)[OFFSET(95)] AS los_p95_days,
    -- Percentile rank for a 7-day stay (exact calculation)
    SAFE_DIVIDE(
        COUNT(CASE WHEN los_days <= 7 THEN 1 END) * 100.0,
        COUNT(los_days) -- COUNT(los_days) ensures denominator handles NULLs correctly if any
    ) AS percentile_rank_7_day_stay
FROM
    CalculatedMetrics
GROUP BY
    discharge_status
ORDER BY
    discharge_status;