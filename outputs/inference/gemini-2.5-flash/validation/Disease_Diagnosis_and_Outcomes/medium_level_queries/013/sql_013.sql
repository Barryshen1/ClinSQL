WITH AdmissionsFiltered AS (
    -- Step 1: Filter for women aged 80-90
    SELECT
        ad.subject_id,
        ad.hadm_id,
        ad.admittime,
        ad.dischtime,
        ad.deathtime,
        ad.hospital_expire_flag,
        pat.gender,
        pat.anchor_age
    FROM
        `physionet-data.mimiciv_3_1_hosp.admissions` ad
    INNER JOIN
        `physionet-data.mimiciv_3_1_hosp.patients` pat
        ON ad.subject_id = pat.subject_id
    WHERE
        pat.gender = 'F'
        AND pat.anchor_age BETWEEN 80 AND 90
),
HFAdmissions AS (
    -- Step 2: Filter for admissions with acute decompensated Heart Failure (HF) diagnosis
    -- Using common ICD codes for Heart Failure (ICD-9: 428.x, ICD-10: I50.x)
    SELECT DISTINCT
        af.subject_id,
        af.hadm_id,
        af.admittime,
        af.dischtime,
        af.deathtime,
        af.hospital_expire_flag
    FROM
        AdmissionsFiltered af
    INNER JOIN
        `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` di
        ON af.subject_id = di.subject_id AND af.hadm_id = di.hadm_id
    WHERE
        (di.icd_version = 9 AND di.icd_code LIKE '428%') -- ICD-9 codes for Congestive Heart Failure
        OR (di.icd_version = 10 AND di.icd_code LIKE 'I50%') -- ICD-10 codes for Heart Failure
),
CalculatedMetrics AS (
    -- Step 3: Calculate Length of Stay (LOS) and time-to-death
    SELECT
        hadm_id,
        hospital_expire_flag,
        -- Calculate time_to_death in days for patients who died, otherwise NULL
        CASE
            WHEN hospital_expire_flag = 1 THEN TIMESTAMP_DIFF(COALESCE(deathtime, dischtime), admittime, HOUR) / 24.0
            ELSE NULL
        END AS time_to_death_days,
        -- Calculate LOS in days. GREATEST(1, CEIL(...)) ensures minimum LOS of 1 day for any admission.
        GREATEST(1, CEIL(TIMESTAMP_DIFF(dischtime, admittime, HOUR) / 24.0)) AS los_days
    FROM
        HFAdmissions
    WHERE
        -- Ensure valid admittime and dischtime for accurate calculations
        admittime IS NOT NULL AND dischtime IS NOT NULL AND dischtime >= admittime
),
CategoryAssigned AS (
    -- Step 4: Assign admissions to LOS categories
    SELECT
        hadm_id,
        hospital_expire_flag,
        time_to_death_days,
        los_days,
        CASE
            WHEN los_days BETWEEN 1 AND 3 THEN 'LOS_1_3_days'
            WHEN los_days BETWEEN 4 AND 7 THEN 'LOS_4_7_days'
            WHEN los_days >= 8 THEN 'LOS_8_plus_days'
            -- Removed 'Unknown_LOS' as LOS will always be >= 1 from CalculatedMetrics logic
        END AS los_category
    FROM
        CalculatedMetrics
    WHERE
        los_days IS NOT NULL -- Exclude admissions where LOS could not be calculated (already handled above)
),
AggregatedStats AS (
    -- Step 5: Aggregate statistics per LOS category
    SELECT
        los_category,
        COUNT(hadm_id) AS num_admissions,
        SUM(hospital_expire_flag) AS num_deaths,
        -- Proportion of admissions resulting in death
        SAFE_DIVIDE(SUM(hospital_expire_flag), COUNT(hadm_id)) AS p_hat_mortality,
        -- Median time-to-death in days (only for those who died)
        -- Using APPROX_PERCENTILE to resolve the BigQuery error, as PERCENTILE_CONT was reported as unsupported.
        APPROX_PERCENTILE(time_to_death_days, 0.5) AS median_time_to_death_days
    FROM
        CategoryAssigned
    WHERE
        los_category IS NOT NULL -- Ensure a category was assigned for aggregation
    GROUP BY
        los_category
)
-- Step 6: Final selection, calculation of CI, and formatting
SELECT
    ags.los_category,
    ags.num_admissions,
    ags.num_deaths,
    -- In-hospital mortality percentage
    ROUND(ags.p_hat_mortality * 100, 2) AS in_hospital_mortality_percent,
    -- 95% Confidence Interval for mortality rate (using Normal Approximation)
    -- Lower bound
    ROUND(
        (ags.p_hat_mortality - (1.96 * SAFE.SQRT(SAFE_DIVIDE(ags.p_hat_mortality * (1.0 - ags.p_hat_mortality), ags.num_admissions)))) * 100,
        2
    ) AS ci_lower_mortality_percent,
    -- Upper bound
    ROUND(
        (ags.p_hat_mortality + (1.96 * SAFE.SQRT(SAFE_DIVIDE(ags.p_hat_mortality * (1.0 - ags.p_hat_mortality), ags.num_admissions)))) * 100,
        2
    ) AS ci_upper_mortality_percent,
    ROUND(ags.median_time_to_death_days, 2) AS median_time_to_death_days
FROM
    AggregatedStats ags
WHERE
    ags.los_category IS NOT NULL -- Final filter for safety, though handled in AggregatedStats
ORDER BY
    CASE ags.los_category -- Ensure consistent order for LOS categories
        WHEN 'LOS_1_3_days' THEN 1
        WHEN 'LOS_4_7_days' THEN 2
        WHEN 'LOS_8_plus_days' THEN 3
        ELSE 4
    END;