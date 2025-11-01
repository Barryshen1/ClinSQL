WITH cohort_los AS (
    SELECT
        -- Stratify by discharge disposition based on the question's categories.
        CASE
            WHEN a.hospital_expire_flag = 1 THEN 'Death'
            WHEN a.discharge_location = 'HOSPICE' THEN 'Hospice'
            -- `LIKE 'HOME%'` captures both 'HOME' and 'HOME HEALTH CARE'.
            WHEN a.discharge_location LIKE 'HOME%' THEN 'Home'
            ELSE NULL -- Other categories are not requested and will be filtered out.
        END AS discharge_category,
        -- Calculate hospital length of stay in days.
        DATETIME_DIFF(a.dischtime, a.admittime, DAY) AS los_days
    FROM
        `physionet-data.mimiciv_3_1_hosp.patients` AS p
    INNER JOIN
        `physionet-data.mimiciv_3_1_hosp.admissions` AS a
            ON p.subject_id = a.subject_id
    LEFT JOIN
        -- We join to icustays to identify admissions WITHOUT an ICU stay.
        `physionet-data.mimiciv_3_1_icu.icustays` AS icu
            ON a.hadm_id = icu.hadm_id
    WHERE
        -- 1. Filter for the patient demographic: males aged 44-54.
        p.gender = 'M'
        AND p.anchor_age BETWEEN 44 AND 54
        -- 2. Filter for admissions on "general wards", defined as those with no ICU stay.
        AND icu.stay_id IS NULL
        -- 3. Ensure LOS can be calculated and is a valid (non-negative) number.
        AND a.dischtime IS NOT NULL AND a.admittime IS NOT NULL
        AND DATETIME_DIFF(a.dischtime, a.admittime, DAY) >= 0
)
SELECT
    discharge_category,
    -- Calculate approximate percentiles for Length of Stay (LOS) in days.
    APPROX_QUANTILES(los_days, 100)[OFFSET(50)] AS los_p50_days,
    APPROX_QUANTILES(los_days, 100)[OFFSET(75)] AS los_p75_days,
    APPROX_QUANTILES(los_days, 100)[OFFSET(90)] AS los_p90_days,
    APPROX_QUANTILES(los_days, 100)[OFFSET(95)] AS los_p95_days,
    -- Calculate the percentile rank of a 7-day stay, representing the
    -- percentage of stays that were 7 days or shorter.
    SAFE_DIVIDE(COUNTIF(los_days <= 7), COUNT(los_days)) * 100 AS percentile_rank_of_7_day_los
FROM
    cohort_los
WHERE
    -- Filter for only the specific discharge categories requested.
    discharge_category IS NOT NULL
GROUP BY
    discharge_category
ORDER BY
    -- Order results for readability.
    discharge_category;