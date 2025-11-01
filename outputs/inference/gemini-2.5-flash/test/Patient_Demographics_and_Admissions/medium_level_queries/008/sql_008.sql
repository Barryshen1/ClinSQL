SELECT
    discharge_category,
    COUNT(hadm_id) AS num_admissions,
    ROUND(AVG(los_days), 2) AS mean_los_days,
    ROUND(APPROX_QUANTILES(los_days, 100)[OFFSET(50)], 2) AS median_los_days_p50,
    ROUND(APPROX_QUANTILES(los_days, 100)[OFFSET(75)], 2) AS p75_los_days,
    ROUND(APPROX_QUANTILES(los_days, 100)[OFFSET(90)], 2) AS p90_los_days,
    ROUND(SUM(CASE WHEN los_days <= 7 THEN 1 ELSE 0 END) * 100.0 / COUNT(los_days), 2) AS percentile_rank_of_7_days
FROM (
    -- Step 3: Combine all filters, calculate LOS and assign discharge category
    SELECT
        pa.subject_id,
        pa.hadm_id,
        TIMESTAMP_DIFF(pa.dischtime, pa.admittime, DAY) AS los_days,
        CASE
            WHEN pa.hospital_expire_flag = 1 THEN 'In-hospital Death'
            WHEN lower(pa.discharge_location) LIKE '%home%' THEN 'Home'
            WHEN lower(pa.discharge_location) LIKE '%rehab%'
            OR lower(pa.discharge_location) LIKE '%nursing%'
            OR lower(pa.discharge_location) LIKE '%facility%'
            OR lower(pa.discharge_location) LIKE '%short term hospital%'
            OR lower(pa.discharge_location) LIKE '%long term care%' THEN 'Facility'
            ELSE 'Other' -- Temporarily label and then filter out 'Other' categories
        END AS discharge_category
    FROM
        `physionet-data.mimiciv_3_1_hosp.admissions` pa
    INNER JOIN
        -- Step 1: Calculate age at admission and filter for gender
        `physionet-data.mimiciv_3_1_hosp.patients` p
        ON pa.subject_id = p.subject_id
    INNER JOIN
        (
            -- Step 2: Identify the last service for each admission
            SELECT
                s.hadm_id,
                s.curr_service,
                ROW_NUMBER() OVER (PARTITION BY s.hadm_id ORDER BY s.transfertime DESC) AS rn
            FROM
                `physionet-data.mimiciv_3_1_hosp.services` s
        ) AS als
        ON pa.hadm_id = als.hadm_id
    WHERE
        p.gender = 'F'
        AND (p.anchor_age + (EXTRACT(YEAR FROM pa.admittime) - p.anchor_year)) BETWEEN 52 AND 62
        AND pa.admission_type != 'ELECTIVE'
        AND als.curr_service = 'MED' -- Filter for medicine inpatients based on last service
        AND als.rn = 1 -- Only consider the last recorded service
        AND pa.dischtime IS NOT NULL AND pa.admittime IS NOT NULL -- Ensure valid LOS calculation
) AS cohort_los
WHERE
    discharge_category IN ('Home', 'Facility', 'In-hospital Death')
GROUP BY
    discharge_category
ORDER BY
    discharge_category;