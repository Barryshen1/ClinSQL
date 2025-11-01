WITH sepsis_admissions AS (
    SELECT DISTINCT
        d.hadm_id
    FROM
        `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
    WHERE
        (d.icd_version = 9 AND d.icd_code LIKE '038%') -- ICD-9 sepsis codes (e.g., 038.x)
        OR (
            d.icd_version = 10 AND (
                d.icd_code LIKE 'A40%' -- ICD-10 sepsis (e.g., A40.x)
                OR d.icd_code LIKE 'A41%' -- ICD-10 other sepsis (e.g., A41.x)
                OR d.icd_code = 'R65.20' -- ICD-10 severe sepsis without septic shock
            )
        )
),
septic_shock_admissions AS (
    SELECT DISTINCT
        d.hadm_id
    FROM
        `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
    WHERE
        (d.icd_version = 9 AND d.icd_code = '785.52') -- ICD-9 septic shock
        OR (d.icd_version = 10 AND d.icd_code = 'R65.21') -- ICD-10 septic shock
),
-- Step 2: Filter for the specific cohort and calculate relevant metrics
cohort_raw AS (
    SELECT
        adm.subject_id,
        adm.hadm_id,
        pat.gender,
        pat.anchor_age,
        adm.admittime,
        adm.dischtime,
        adm.deathtime,
        adm.hospital_expire_flag,
        -- Calculate LOS ensuring valid times.
        DATETIME_DIFF(adm.dischtime, adm.admittime, DAY) AS LOS_days,
        -- Calculate time to death only if the patient expired in-hospital.
        -- Explicitly set to NULL if not deceased or deathtime is missing.
        CASE
            WHEN adm.hospital_expire_flag = 1 AND adm.deathtime IS NOT NULL
            THEN DATETIME_DIFF(adm.deathtime, adm.admittime, DAY)
            ELSE NULL
        END AS time_to_death_days
    FROM
        `physionet-data.mimiciv_3_1_hosp.admissions` AS adm
        JOIN `physionet-data.mimiciv_3_1_hosp.patients` AS pat ON adm.subject_id = pat.subject_id
    WHERE
        pat.gender = 'M'
        AND pat.anchor_age BETWEEN 50 AND 60
        AND adm.hadm_id IN (SELECT hadm_id FROM sepsis_admissions)
        AND adm.hadm_id NOT IN (SELECT hadm_id FROM septic_shock_admissions)
        -- Added checks for valid admission and discharge times for robust LOS calculation
        AND adm.admittime IS NOT NULL
        AND adm.dischtime IS NOT NULL
        AND adm.dischtime >= adm.admittime -- Ensure discharge is not before admission
),
-- Step 3: Categorize LOS and prepare for final aggregation
categorized_cohort AS (
    SELECT
        hadm_id,
        hospital_expire_flag,
        -- time_to_death_days is already NULL for survivors or missing deathtime,
        -- so we can use it directly for deceased patients.
        time_to_death_days AS time_to_death_days_deceased,
        CASE
            WHEN LOS_days < 8 THEN '<8 days'
            ELSE '>=8 days'
        END AS los_category
    FROM
        cohort_raw
    WHERE
        LOS_days IS NOT NULL -- Exclude records where LOS could not be reliably calculated
)
-- Step 4: Calculate final statistics
SELECT
    los_category,
    COUNT(hadm_id) AS total_admissions,
    COUNT(CASE WHEN hospital_expire_flag = 1 THEN 1 END) AS deceased_admissions,

    -- In-hospital mortality percentage (using SAFE_DIVIDE for robustness)
    SAFE_DIVIDE(COUNT(CASE WHEN hospital_expire_flag = 1 THEN 1 END) * 100.0, COUNT(hadm_id)) AS in_hospital_mortality_percent,

    -- 95% CI for mortality percentage (Wald interval)
    -- Calculate proportion p and standard error for clarity and efficiency
    COALESCE(
        ROUND(
            (
                (SAFE_DIVIDE(COUNT(CASE WHEN hospital_expire_flag = 1 THEN 1 END) * 1.0, COUNT(hadm_id))) -
                (1.96 * SQRT(
                    SAFE_DIVIDE(
                        (SAFE_DIVIDE(COUNT(CASE WHEN hospital_expire_flag = 1 THEN 1 END) * 1.0, COUNT(hadm_id))) *
                        (1 - (SAFE_DIVIDE(COUNT(CASE WHEN hospital_expire_flag = 1 THEN 1 END) * 1.0, COUNT(hadm_id)))),
                        NULLIF(COUNT(hadm_id), 0)
                    )
                ))
            ) * 100, 2
        ),
        0
    ) AS ci_95_lower_bound_percent,
    COALESCE(
        ROUND(
            (
                (SAFE_DIVIDE(COUNT(CASE WHEN hospital_expire_flag = 1 THEN 1 END) * 1.0, COUNT(hadm_id))) +
                (1.96 * SQRT(
                    SAFE_DIVIDE(
                        (SAFE_DIVIDE(COUNT(CASE WHEN hospital_expire_flag = 1 THEN 1 END) * 1.0, COUNT(hadm_id))) *
                        (1 - (SAFE_DIVIDE(COUNT(CASE WHEN hospital_expire_flag = 1 THEN 1 END) * 1.0, COUNT(hadm_id)))),
                        NULLIF(COUNT(hadm_id), 0)
                    )
                ))
            ) * 100, 2
        ),
        0
    ) AS ci_95_upper_bound_percent,

    -- Median time-to-death among non-survivors (NULLs in time_to_death_days_deceased are ignored)
    PERCENTILE_CONT(time_to_death_days_deceased, 0.5) AS median_time_to_death_days_non_survivors
FROM
    categorized_cohort
GROUP BY
    los_category
ORDER BY
    los_category;