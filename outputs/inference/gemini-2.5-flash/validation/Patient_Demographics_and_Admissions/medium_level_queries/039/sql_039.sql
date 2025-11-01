WITH admissions_cohort AS (
    SELECT
        adm.subject_id,
        adm.hadm_id,
        adm.admittime,
        adm.dischtime,
        adm.hospital_expire_flag,
        adm.discharge_location,
        pat.gender,
        (EXTRACT(YEAR FROM adm.admittime) - pat.anchor_year + pat.anchor_age) AS age_at_admission,
        -- Calculate Length of Stay in fractional days
        TIMESTAMP_DIFF(adm.dischtime, adm.admittime, HOUR) / 24.0 AS los_days
    FROM
        `physionet-data.mimiciv_3_1_hosp`.admissions adm
    INNER JOIN
        `physionet-data.mimiciv_3_1_hosp`.patients pat
        ON adm.subject_id = pat.subject_id
    WHERE
        pat.gender = 'F' -- Female patients
        AND adm.admission_type IN ('URGENT', 'EMERGENCY') -- Urgent or Emergency admissions
        AND (EXTRACT(YEAR FROM adm.admittime) - pat.anchor_year + pat.anchor_age) BETWEEN 37 AND 47 -- Age at admission 37-47
        AND adm.admittime IS NOT NULL
        AND adm.dischtime IS NOT NULL
        AND TIMESTAMP_DIFF(adm.dischtime, adm.admittime, HOUR) >= 0 -- Exclude invalid LOS
),
-- Assign discharge group based on specified criteria and filter out unclassified discharges early
cleaned_cohort AS (
    SELECT
        ac.hadm_id,
        ac.los_days,
        CASE
            WHEN ac.hospital_expire_flag = 1 THEN 'In-Hospital Death'
            WHEN ac.discharge_location = 'Home' THEN 'Home'
            WHEN ac.discharge_location IN ('SNF', 'Skilled Nursing Facility', 'Rehab', 'Rehab Care Alliance', 'Long Term Care Hospital') THEN 'Facility'
            ELSE NULL -- Assign NULL to unclassified discharge locations
        END AS discharge_group
    FROM
        admissions_cohort ac
    WHERE
        -- Only include rows that map to one of the target discharge groups before performing calculations
        CASE
            WHEN ac.hospital_expire_flag = 1 THEN 'In-Hospital Death'
            WHEN ac.discharge_location = 'Home' THEN 'Home'
            WHEN ac.discharge_location IN ('SNF', 'Skilled Nursing Facility', 'Rehab', 'Rehab Care Alliance', 'Long Term Care Hospital') THEN 'Facility'
            ELSE NULL
        END IS NOT NULL
)
-- Calculate aggregates using window functions and then select distinct results for each group
SELECT DISTINCT
    discharge_group,
    COUNT(hadm_id) OVER (PARTITION BY discharge_group) AS num_admissions,
    AVG(los_days) OVER (PARTITION BY discharge_group) AS mean_los_days,
    -- Calculate percentiles using PERCENTILE_CONT window function
    -- Removed ORDER BY from OVER clause in PERCENTILE_CONT, as it's not valid for BigQuery's syntax.
    -- BigQuery implicitly sorts on the first argument (los_days) for PERCENTILE_CONT.
    PERCENTILE_CONT(los_days, 0.25) OVER (PARTITION BY discharge_group) AS los_25th_percentile,
    PERCENTILE_CONT(los_days, 0.50) OVER (PARTITION BY discharge_group) AS los_50th_percentile_median,
    PERCENTILE_CONT(los_days, 0.75) OVER (PARTITION BY discharge_group) AS los_75th_percentile,
    -- Calculate percentile rank of a 7-day stay: percentage of stays <= 7 days
    (COUNT(CASE WHEN los_days <= 7 THEN 1 END) OVER (PARTITION BY discharge_group) * 100.0 / COUNT(hadm_id) OVER (PARTITION BY discharge_group)) AS percentile_rank_7_day_stay
FROM
    cleaned_cohort
ORDER BY
    discharge_group;