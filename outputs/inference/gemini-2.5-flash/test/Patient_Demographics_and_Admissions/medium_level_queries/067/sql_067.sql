WITH cohort_admissions AS (
    SELECT
        adm.subject_id,
        adm.hadm_id,
        p.gender,
        p.anchor_age,
        -- Calculate Length of Stay (LOS) in fractional days for precision
        CAST(TIMESTAMP_DIFF(adm.dischtime, adm.admittime, HOUR) AS BIGNUMERIC) / 24.0 AS los_days,
        -- Categorize discharge status as required for percentile calculation
        CASE
            WHEN adm.hospital_expire_flag = 1 THEN 'In-hospital Death'
            WHEN adm.discharge_location IN ('Home', 'Home With Service', 'Home Health Care') THEN 'Home'
            WHEN adm.discharge_location = 'Hospice' THEN 'Hospice'
            ELSE 'Other' -- Group other discharge locations not requested for specific percentile analysis
        END AS discharge_status_group
    FROM
        `physionet-data.mimiciv_3_1_hosp.admissions` AS adm
    INNER JOIN
        `physionet-data.mimiciv_3_1_hosp.patients` AS p
        ON adm.subject_id = p.subject_id
    WHERE
        p.gender = 'M' -- Filter for male patients
        AND p.anchor_age BETWEEN 49 AND 59 -- Filter for age between 49 and 59
        -- Ensure the patient was on the 'MED' (Medicine) service at some point during the admission
        AND adm.hadm_id IN (
            SELECT DISTINCT s.hadm_id
            FROM `physionet-data.mimiciv_3_1_hosp.services` AS s
            WHERE s.curr_service = 'MED'
        )
),
-- Step 2: Calculate overall proportions for LOS thresholds
proportions_summary AS (
    SELECT
        'Proportion LOS >= 7 days' AS metric_type,
        'All' AS discharge_group,
        SAFE_DIVIDE(COUNTIF(los_days >= 7), COUNT(*)) AS metric_value
    FROM
        cohort_admissions
    UNION ALL
    SELECT
        'Proportion LOS >= 14 days' AS metric_type,
        'All' AS discharge_group,
        SAFE_DIVIDE(COUNTIF(los_days >= 14), COUNT(*)) AS metric_value
    FROM
        cohort_admissions
),
-- Step 3: Calculate 7th percentile for LOS by specific discharge groups
percentiles_summary AS (
    SELECT
        '7th percentile LOS' AS metric_type,
        discharge_status_group AS discharge_group,
        -- Corrected: Use APPROX_QUANTILES for percentile computation in BigQuery
        APPROX_QUANTILES(los_days, 100)[OFFSET(7)] AS metric_value -- 7th percentile
    FROM
        cohort_admissions
    WHERE
        discharge_status_group IN ('Home', 'Hospice', 'In-hospital Death') -- Filter for relevant discharge groups
    GROUP BY
        discharge_status_group
)
-- Step 4: Combine all results into a single output table
SELECT * FROM proportions_summary
UNION ALL
SELECT * FROM percentiles_summary
ORDER BY metric_type, discharge_group;