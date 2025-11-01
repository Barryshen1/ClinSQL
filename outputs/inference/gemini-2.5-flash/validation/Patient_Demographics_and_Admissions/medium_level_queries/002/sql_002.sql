WITH med_service_admissions AS (
    -- First, identify all hadm_id that involved a 'MED' service
    SELECT DISTINCT hadm_id
    FROM `physionet-data.mimiciv_3_1_hosp.services`
    WHERE curr_service = 'MED'
),
cohort_admissions AS (
    -- Select the relevant admissions and calculate LOS and discharge group
    SELECT
        a.hadm_id,
        -- Calculate LOS in days
        TIMESTAMP_DIFF(a.dischtime, a.admittime, HOUR) / 24.0 AS los_days,
        -- Categorize discharge outcome
        CASE
            WHEN a.hospital_expire_flag = 1 THEN 'In-Hospital Death'
            WHEN a.discharge_location = 'HOME' THEN 'Discharged Home'
            WHEN a.discharge_location IN ('SNF', 'REHAB', 'OTHER FACILITY', 'PSYCH', 'HOSPICE', 'Other Facility') THEN 'Discharged to Facility'
            ELSE 'Other/Unknown' -- Catch any other discharge locations
        END AS discharge_group
    FROM
        `physionet-data.mimiciv_3_1_hosp.admissions` AS a
    INNER JOIN
        `physionet-data.mimiciv_3_1_hosp.patients` AS p
        ON a.subject_id = p.subject_id
    INNER JOIN
        med_service_admissions AS msa
        ON a.hadm_id = msa.hadm_id
    WHERE
        p.gender = 'M'
        AND p.anchor_age BETWEEN 59 AND 69 -- Admissions for males aged 59-69
        AND a.admittime IS NOT NULL AND a.dischtime IS NOT NULL -- Ensure valid admission/discharge times
        AND TIMESTAMP_DIFF(a.dischtime, a.admittime, SECOND) > 0 -- Ensure positive LOS calculation
)
SELECT
    discharge_group,
    COUNT(DISTINCT hadm_id) AS num_admissions,
    ROUND(AVG(los_days), 2) AS mean_los_days,
    -- Use APPROX_QUANTILES with OFFSET for approximate percentiles
    ROUND(APPROX_QUANTILES(los_days, 100)[OFFSET(25)], 2) AS los_p25_days,
    ROUND(APPROX_QUANTILES(los_days, 100)[OFFSET(50)], 2) AS los_p50_days, -- Median
    ROUND(APPROX_QUANTILES(los_days, 100)[OFFSET(75)], 2) AS los_p75_days,
    ROUND(APPROX_QUANTILES(los_days, 100)[OFFSET(90)], 2) AS los_p90_days,
    ROUND(COUNTIF(los_days <= 10) * 100.0 / COUNT(los_days), 2) AS percent_los_le_10_days
FROM
    cohort_admissions
GROUP BY
    discharge_group
ORDER BY
    discharge_group;