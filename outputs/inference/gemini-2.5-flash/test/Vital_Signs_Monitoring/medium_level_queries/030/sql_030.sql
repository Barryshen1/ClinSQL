WITH
    -- 1. Identify all eligible ICU stays: Female patients aged 81-91
    eligible_stays AS (
        SELECT
            s.subject_id,
            s.hadm_id,
            s.stay_id,
            s.intime
        FROM
            `physionet-data.mimiciv_3_1_icu.icustays` s
        INNER JOIN
            `physionet-data.mimiciv_3_1_hosp.patients` p
            ON s.subject_id = p.subject_id
        WHERE
            p.gender = 'F'
            AND p.anchor_age BETWEEN 81 AND 91
    ),
    -- 2. Calculate the mean temperature in the first 24 hours for each eligible stay
    per_stay_temp AS (
        SELECT
            es.stay_id,
            AVG(ce.valuenum) AS mean_temp_24hr
        FROM
            eligible_stays es
        INNER JOIN
            `physionet-data.mimiciv_3_1_icu.chartevents` ce
            ON es.stay_id = ce.stay_id
        WHERE
            ce.itemid = 223762 -- ItemID for Temperature C
            AND ce.valuenum IS NOT NULL -- Exclude null values from averaging
            -- Filter out implausible temperature values often found in chartevents
            AND ce.valuenum > 0
            AND ce.valuenum < 50
            AND ce.charttime BETWEEN es.intime AND DATETIME_ADD(es.intime, INTERVAL 24 HOUR)
        GROUP BY
            es.stay_id
    ),
    -- 3. Combine eligible stays with their calculated mean temperature and classify them
    cohort_with_temp_and_category AS (
        SELECT
            es.stay_id,
            pst.mean_temp_24hr,
            CASE
                WHEN pst.mean_temp_24hr IS NULL THEN 'Missing Information'
                WHEN pst.mean_temp_24hr < 36.0 THEN '<36.0 C'
                WHEN pst.mean_temp_24hr >= 36.0 AND pst.mean_temp_24hr <= 37.9 THEN '36.0-37.9 C'
                WHEN pst.mean_temp_24hr >= 38.0 THEN '>=38.0 C'
                ELSE 'Other/Error' -- Fallback for any unexpected values, though unlikely with filters
            END AS temp_category
        FROM
            eligible_stays es
        LEFT JOIN
            per_stay_temp pst
            ON es.stay_id = pst.stay_id
    ),
    -- 4. Calculate overall missing information (MI) metrics
    mi_metrics AS (
        SELECT
            COUNT(stay_id) AS total_eligible_stays_count,
            SUM(CASE WHEN mean_temp_24hr IS NULL THEN 1 ELSE 0 END) AS missing_temp_stays_count,
            ROUND(SUM(CASE WHEN mean_temp_24hr IS NULL THEN 1 ELSE 0 END) * 100.0 / COUNT(stay_id), 2) AS overall_mi_rate_pct
        FROM
            cohort_with_temp_and_category
    )
-- 5. Aggregate results by temperature category and include overall MI rate
SELECT
    cc.temp_category,
    COUNT(cc.stay_id) AS N_stays,
    ROUND(AVG(cc.mean_temp_24hr), 2) AS mean_temp,
    -- PERCENTILE_CONT without OVER() clause acts as an aggregate function per group
    ROUND(PERCENTILE_CONT(cc.mean_temp_24hr, 0.25), 2) AS q1_temp,
    ROUND(PERCENTILE_CONT(cc.mean_temp_24hr, 0.5), 2) AS median_temp,
    ROUND(PERCENTILE_CONT(cc.mean_temp_24hr, 0.75), 2) AS q3_temp,
    -- Calculate IQR using the aggregate percentile functions
    ROUND(
        PERCENTILE_CONT(cc.mean_temp_24hr, 0.75) -
        PERCENTILE_CONT(cc.mean_temp_24hr, 0.25),
    2) AS iqr_temp,
    mm.overall_mi_rate_pct
FROM
    cohort_with_temp_and_category cc
CROSS JOIN
    mi_metrics mm -- Cross join to include the overall MI rate in every result row
GROUP BY
    cc.temp_category,
    mm.overall_mi_rate_pct -- All non-aggregated columns must be in GROUP BY
ORDER BY
    CASE
        WHEN cc.temp_category = '<36.0 C' THEN 1
        WHEN cc.temp_category = '36.0-37.9 C' THEN 2
        WHEN cc.temp_category = '>=38.0 C' THEN 3
        WHEN cc.temp_category = 'Missing Information' THEN 4
        ELSE 5
    END;