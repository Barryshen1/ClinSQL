WITH AdmissionsCohort AS (
    -- Select relevant admissions and patients, filtering by demographic and admission type,
    -- and calculating Length of Stay (LOS) and categorizing discharge outcome.
    SELECT
        p.subject_id,
        adm.hadm_id,
        p.gender,
        p.anchor_age, -- Assuming anchor_age directly represents the patient's age within the 89-99 range without capping.
        adm.admittime,
        adm.dischtime,
        DATE_DIFF(adm.dischtime, adm.admittime, DAY) AS los_days, -- Calculate Length of Stay in whole days
        adm.admission_type,
        adm.discharge_location,
        adm.hospital_expire_flag,
        -- Categorize each admission's discharge outcome based on the specified criteria
        CASE
            WHEN adm.hospital_expire_flag = 1 THEN 'In-hospital Death'
            WHEN adm.discharge_location LIKE '%HOSPICE%' THEN 'Hospice'
            WHEN adm.discharge_location LIKE '%HOME%' THEN 'Home'
            ELSE 'Other' -- Category for discharge locations not explicitly requested
        END AS discharge_outcome_category
    FROM
        `physionet-data.mimiciv_3_1_hosp.admissions` adm
    JOIN
        `physionet-data.mimiciv_3_1_hosp.patients` p
        ON adm.subject_id = p.subject_id
    WHERE
        p.gender = 'M' -- Filter for male patients
        AND p.anchor_age BETWEEN 89 AND 99 -- Filter for the specified age range
        AND adm.admission_type NOT IN ('EMERGENCY', 'URGENT') -- Filter for non-emergent admissions
        AND adm.dischtime IS NOT NULL -- Ensure discharge time is available for LOS calculation
        AND adm.admittime IS NOT NULL -- Ensure admission time is available for LOS calculation
        AND DATE_DIFF(adm.dischtime, adm.admittime, DAY) >= 0 -- Exclude invalid LOS (discharge before admission)
)
-- Calculate the required aggregate statistics for LOS, grouped by the specified discharge outcomes.
SELECT
    discharge_outcome_category,
    COUNT(hadm_id) AS num_admissions,
    ROUND(AVG(los_days), 2) AS mean_los_days,
    APPROX_QUANTILES(los_days, 100)[OFFSET(50)] AS median_los_days, -- 50th percentile (median)
    APPROX_QUANTILES(los_days, 100)[OFFSET(75)] AS p75_los_days,   -- 75th percentile
    APPROX_QUANTILES(los_days, 100)[OFFSET(90)] AS p90_los_days,   -- 90th percentile
    -- Calculate the percentage of admissions with LOS less than 5 days
    ROUND(COUNTIF(los_days < 5) * 100.0 / COUNT(los_days), 2) AS percent_los_lt_5_days
FROM
    AdmissionsCohort
WHERE
    -- Only include the discharge outcomes explicitly requested in the final report
    discharge_outcome_category IN ('Home', 'Hospice', 'In-hospital Death')
GROUP BY
    discharge_outcome_category
ORDER BY
    discharge_outcome_category;