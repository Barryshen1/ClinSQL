WITH base_admissions AS (
    SELECT
        a.subject_id,
        a.hadm_id,
        a.admittime,
        a.dischtime,
        -- Ensure hosp_los_days is an integer for consistent median calculation and LOS grouping
        CAST(DATETIME_DIFF(a.dischtime, a.admittime, DAY) AS INT64) AS hosp_los_days,
        a.hospital_expire_flag
    FROM
        `physionet-data.mimiciv_3_1_hosp.admissions` AS a
    INNER JOIN
        `physionet-data.mimiciv_3_1_hosp.patients` AS p
        ON a.subject_id = p.subject_id
    WHERE
        p.gender = 'M'
        AND p.anchor_age BETWEEN 77 AND 87
),
-- Step 2: Identify Heart Failure (HF) admissions from the base cohort
hf_admissions AS (
    SELECT DISTINCT
        b.subject_id,
        b.hadm_id,
        b.admittime,
        b.dischtime,
        b.hosp_los_days,
        b.hospital_expire_flag
    FROM
        base_admissions AS b
    INNER JOIN
        `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` AS di_hf
        ON b.hadm_id = di_hf.hadm_id
    WHERE
        (di_hf.icd_code LIKE '428%' AND di_hf.icd_version = 9) -- ICD-9 HF codes
        OR (di_hf.icd_code LIKE 'I50%' AND di_hf.icd_version = 10) -- ICD-10 HF codes
),
-- Pre-aggregate diagnosis flags per hadm_id to avoid fan-out before further processing
diagnoses_flags AS (
    SELECT
        hadm_id,
        MAX(CASE
                WHEN (di.icd_code LIKE '585%' AND di.icd_version = 9) -- ICD-9 CKD codes (e.g., 585.x)
                OR (di.icd_code LIKE 'N18%' AND di.icd_version = 10) -- ICD-10 CKD codes (e.g., N18.x)
                THEN 1 ELSE 0 END
        ) AS has_ckd_flag,
        MAX(CASE
                WHEN (di.icd_code LIKE '250%' AND di.icd_version = 9) -- ICD-9 Diabetes (e.g., 250.x)
                OR (di.icd_code LIKE 'E08%' AND di.icd_version = 10) -- ICD-10 Diabetes Mellitus (type 1, 2, other)
                OR (di.icd_code LIKE 'E09%' AND di.icd_version = 10)
                OR (di.icd_code LIKE 'E10%' AND di.icd_version = 10)
                OR (di.icd_code LIKE 'E11%' AND di.icd_version = 10)
                OR (di.icd_code LIKE 'E13%' AND di.icd_version = 10)
                THEN 1 ELSE 0 END
        ) AS has_diabetes_flag
    FROM
        `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` AS di
    GROUP BY
        hadm_id
),
-- Step 3: Add Day-1 ICU status, CKD, and Diabetes flags for each HF admission
final_cohort_with_flags AS (
    SELECT
        hf.subject_id,
        hf.hadm_id,
        hf.hosp_los_days,
        hf.hospital_expire_flag,
        -- Determine Day-1 ICU status: 'ICU on Day 1' if any ICU stay overlaps with the first 24 hours of hospital admission
        CASE
            WHEN EXISTS (
                SELECT 1
                FROM `physionet-data.mimiciv_3_1_icu.icustays` AS icu
                WHERE icu.hadm_id = hf.hadm_id
                  -- An ICU stay is considered 'on Day 1' if any point of the ICU stay falls within admittime and admittime + 1 day
                  AND icu.intime <= DATETIME_ADD(hf.admittime, INTERVAL 1 DAY)
                  AND icu.outtime >= hf.admittime
            ) THEN 'ICU on Day 1'
            ELSE 'Non-ICU on Day 1'
        END AS day1_icu_status,
        -- Use pre-aggregated flags; COALESCE handles cases where no matching diagnosis exists
        COALESCE(df.has_ckd_flag, 0) AS has_ckd_flag,
        COALESCE(df.has_diabetes_flag, 0) AS has_diabetes_flag
    FROM
        hf_admissions AS hf
    LEFT JOIN
        diagnoses_flags AS df
        ON hf.hadm_id = df.hadm_id
    WHERE
        hf.hosp_los_days >= 1 -- Only consider admissions with a valid LOS of at least 1 full day
),
-- Step 4: Categorize by LOS groups
grouped_cohort AS (
    SELECT
        day1_icu_status,
        CASE
            WHEN hosp_los_days BETWEEN 1 AND 3 THEN '1-3 days'
            WHEN hosp_los_days BETWEEN 4 AND 7 THEN '4-7 days'
            WHEN hosp_los_days >= 8 THEN '>=8 days'
            ELSE 'Invalid LOS' -- This should not be reached due to previous filtering (hosp_los_days >= 1)
        END AS los_group,
        hosp_los_days,
        hospital_expire_flag,
        has_ckd_flag,
        has_diabetes_flag,
        hadm_id
    FROM
        final_cohort_with_flags
    WHERE
        hosp_los_days IS NOT NULL -- Exclude any admissions with undefined LOS
),
-- Step 5: For median calculation, rank LOS within each group
ranked_los AS (
    SELECT
        day1_icu_status,
        los_group,
        hosp_los_days,
        ROW_NUMBER() OVER (PARTITION BY day1_icu_status, los_group ORDER BY hosp_los_days) AS rn,
        COUNT(hosp_los_days) OVER (PARTITION BY day1_icu_status, los_group) AS group_size
    FROM
        grouped_cohort
),
-- Step 6: Identify median LOS for each group using the ranked data
median_los_per_group AS (
    SELECT
        day1_icu_status,
        los_group,
        -- AVG works for both odd (single value) and even (average of two middle values) group sizes
        AVG(hosp_los_days) as median_los_days_calc
    FROM
        ranked_los
    WHERE
        -- Selects the middle rank for odd sized groups, or the two middle ranks for even sized groups
        rn IN (FLOOR((group_size + 1) / 2), CEIL((group_size + 1) / 2))
    GROUP BY
        day1_icu_status,
        los_group
)
-- Step 7: Final aggregation
SELECT
    gc.day1_icu_status,
    gc.los_group,
    COUNT(gc.hadm_id) AS total_admissions,
    SAFE_DIVIDE(SUM(gc.hospital_expire_flag) * 100.0, COUNT(gc.hadm_id)) AS in_hospital_mortality_percent,
    mlpg.median_los_days_calc, -- Use the pre-calculated median
    SAFE_DIVIDE(SUM(gc.has_ckd_flag) * 100.0, COUNT(gc.hadm_id)) AS ckd_prevalence_percent,
    SAFE_DIVIDE(SUM(gc.has_diabetes_flag) * 100.0, COUNT(gc.hadm_id)) AS diabetes_prevalence_percent
FROM
    grouped_cohort AS gc
INNER JOIN -- Use INNER JOIN here as we expect every group to have a median LOS
    median_los_per_group AS mlpg
    ON gc.day1_icu_status = mlpg.day1_icu_status
    AND gc.los_group = mlpg.los_group
GROUP BY
    gc.day1_icu_status,
    gc.los_group,
    mlpg.median_los_days_calc -- Include pre-calculated median in GROUP BY
ORDER BY
    gc.day1_icu_status,
    -- Custom order for LOS groups for correct reporting
    CASE
        WHEN gc.los_group = '1-3 days' THEN 1
        WHEN gc.los_group = '4-7 days' THEN 2
        WHEN gc.los_group = '>=8 days' THEN 3
        ELSE 4 -- For any 'Invalid LOS' if it somehow appears
    END
;