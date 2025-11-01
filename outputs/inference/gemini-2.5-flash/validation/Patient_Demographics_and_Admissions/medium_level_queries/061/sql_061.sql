WITH cohort_admissions AS (
    SELECT
        adm.subject_id,
        adm.hadm_id,
        -- Calculate Length of Stay in days
        DATETIME_DIFF(adm.dischtime, adm.admittime, DAY) AS los_days,
        -- Categorize discharge outcome
        CASE
            WHEN adm.hospital_expire_flag = 1 THEN 'In-hospital Death'
            WHEN adm.discharge_location IN ('HOME', 'HOME HEALTH CARE', 'AGAINST ADVICE') THEN 'Home'
            -- All other living discharges (including transfers to other facilities, hospice, etc.) are grouped into 'Facility'.
            ELSE 'Facility'
        END AS discharge_outcome
    FROM
        `physionet-data.mimiciv_3_1_hosp.admissions` adm
    INNER JOIN
        `physionet-data.mimiciv_3_1_hosp.patients` pat
        ON adm.subject_id = pat.subject_id
    WHERE
        -- Filter for specified patient cohort
        pat.gender = 'M'
        AND pat.anchor_age BETWEEN 86 AND 96
        AND adm.admission_type = 'URGENT'
        AND adm.insurance = 'Medicare'
        -- Ensure valid admission and discharge times for LOS calculation
        AND adm.admittime IS NOT NULL
        AND adm.dischtime IS NOT NULL
        -- Exclude any potential data errors where discharge is before admission
        AND DATETIME_DIFF(adm.dischtime, adm.admittime, DAY) >= 0
)
-- Step 2: Calculate aggregate statistics (mean, median, p75, p90, and percentage of 10-day stay or less)
--         for LOS, grouped by the defined discharge outcomes.
SELECT
    discharge_outcome,
    ROUND(AVG(los_days), 2) AS mean_los_days,
    -- APPROX_QUANTILES is used for median (50th percentile), 75th percentile, and 90th percentile.
    -- This is an approximate quantile calculation, which is standard practice and efficient in BigQuery.
    ROUND(APPROX_QUANTILES(los_days, 100)[OFFSET(50)], 2) AS median_los_days,
    ROUND(APPROX_QUANTILES(los_days, 100)[OFFSET(75)], 2) AS p75_los_days,
    ROUND(APPROX_QUANTILES(los_days, 100)[OFFSET(90)], 2) AS p90_los_days,
    -- Calculate the percentage of patients with a stay of 10 days or less within each outcome group.
    ROUND(SUM(CASE WHEN los_days <= 10 THEN 1 ELSE 0 END) * 100.0 / COUNT(los_days), 2) AS percent_10_day_stay_or_less
FROM
    cohort_admissions
GROUP BY
    discharge_outcome
ORDER BY
    discharge_outcome;