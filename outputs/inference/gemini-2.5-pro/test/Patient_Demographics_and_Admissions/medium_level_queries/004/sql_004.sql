with non‑emergent admissions, report mean, median, p75, p90 LOS by discharge (home, hospice, in‑hospital death) and percent with LOS <5 days.
-- This query calculates length of stay (LOS) for a specific cohort of patients: males aged 89-99 with non-emergent hospital admissions.
-- It reports key statistical measures of LOS, stratified by discharge disposition.

-- Step 1: Create a CTE to define the patient cohort, calculate LOS,
-- and categorize discharge status.
WITH cohort_admissions AS (
    SELECT
        adm.hadm_id,
        -- Calculate Length of Stay in days
        DATETIME_DIFF(adm.dischtime, adm.admittime, DAY) AS los_days,
        -- Categorize discharge disposition into Home, Hospice, or In-hospital Death
        CASE
            WHEN adm.hospital_expire_flag = 1 THEN 'In-hospital Death'
            WHEN adm.discharge_location = 'HOSPICE' THEN 'Hospice'
            WHEN adm.discharge_location LIKE 'HOME%' THEN 'Home'
            ELSE NULL
        END AS discharge_group
    FROM
        `physionet-data.mimiciv_3_1_hosp.admissions` AS adm
    INNER JOIN
        `physionet-data.mimiciv_3_1_hosp.patients` AS pat
        ON adm.subject_id = pat.subject_id
    WHERE
        -- Filter for male patients aged 89-99
        pat.gender = 'M'
        AND pat.anchor_age BETWEEN 89 AND 99
        -- Filter for non-emergent admissions
        AND adm.admission_type NOT IN ('EMERGENCY', 'URGENT')
        -- Ensure LOS can be calculated by excluding rows with missing time data
        AND adm.dischtime IS NOT NULL AND adm.admittime IS NOT NULL
)
-- Step 2: Aggregate the results by the defined discharge groups
-- and calculate the requested statistics.
SELECT
    discharge_group,
    COUNT(hadm_id) AS number_of_admissions,
    ROUND(AVG(los_days), 2) AS mean_los_days,
    -- APPROX_QUANTILES is an efficient way to calculate multiple percentiles
    APPROX_QUANTILES(los_days, 100)[OFFSET(50)] AS median_los_days,
    APPROX_QUANTILES(los_days, 100)[OFFSET(75)] AS p75_los_days,
    APPROX_QUANTILES(los_days, 100)[OFFSET(90)] AS p90_los_days,
    ROUND(COUNTIF(los_days < 5) * 100.0 / COUNT(hadm_id), 2) AS percent_los_lt_5
FROM
    cohort_admissions
WHERE
    -- Exclude admissions that did not fall into our target discharge groups
    discharge_group IS NOT NULL
GROUP BY
    discharge_group
ORDER BY
    -- Order results alphabetically by discharge group for consistent output
    discharge_group;