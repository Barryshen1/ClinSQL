WITH admission_cohort AS (
    SELECT
        adm.subject_id,
        adm.hadm_id,
        adm.admittime,
        adm.dischtime,
        adm.hospital_expire_flag,
        -- Calculate Length of Stay in days
        TIMESTAMP_DIFF(adm.dischtime, adm.admittime, HOUR) / 24.0 AS los_in_days
    FROM
        `physionet-data.mimiciv_3_1_hosp.admissions` AS adm
    INNER JOIN
        `physionet-data.mimiciv_3_1_hosp.patients` AS pat
        ON adm.subject_id = pat.subject_id
    WHERE
        -- Filter for male patients
        pat.gender = 'M'
        -- Filter for patients aged between 41 and 51
        -- 'anchor_age' represents the age at the time of the anchor year.
        AND pat.anchor_age BETWEEN 41 AND 51
        -- Filter for admissions from the Emergency Department
        AND adm.admission_location = 'EMERGENCY ROOM'
        -- Ensure admission and discharge times are available for LOS calculation
        AND adm.admittime IS NOT NULL
        AND adm.dischtime IS NOT NULL
        -- Ensure LOS is non-negative (discharge time is not before admission time)
        AND TIMESTAMP_DIFF(adm.dischtime, adm.admittime, SECOND) >= 0
)
SELECT
    CASE
        WHEN ac.hospital_expire_flag = 0 THEN 'Discharged Alive'
        WHEN ac.hospital_expire_flag = 1 THEN 'In-hospital Mortality'
        ELSE 'Unknown' -- Should not occur if flag is always 0 or 1
    END AS outcome_group,
    -- Calculate Mean LOS, rounded to 2 decimal places
    ROUND(AVG(ac.los_in_days), 2) AS mean_los_days,
    -- Calculate Approximate Median LOS, rounded to 2 decimal places using APPROX_QUANTILES
    ROUND(APPROX_QUANTILES(ac.los_in_days, 2)[OFFSET(1)], 2) AS median_los_days,
    -- Calculate Percentage of LOS <= 5 days, rounded to 2 decimal places
    ROUND(COUNTIF(ac.los_in_days <= 5) * 100.0 / COUNT(ac.los_in_days), 2) AS percent_leq_5_day_los
FROM
    admission_cohort AS ac
GROUP BY
    ac.hospital_expire_flag -- Group by the flag to stratify results
ORDER BY
    ac.hospital_expire_flag;