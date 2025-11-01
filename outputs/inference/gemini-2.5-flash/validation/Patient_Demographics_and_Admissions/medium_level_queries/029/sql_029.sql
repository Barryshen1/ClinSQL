WITH cohort_data AS (
    SELECT
        p.subject_id,
        adm.hadm_id,
        icu.stay_id,
        icu.los,
        adm.hospital_expire_flag
    FROM
        `physionet-data.mimiciv_3_1_hosp.patients` p
    INNER JOIN
        `physionet-data.mimiciv_3_1_hosp.admissions` adm
        ON p.subject_id = adm.subject_id
    INNER JOIN
        `physionet-data.mimiciv_3_1_icu.icustays` icu
        ON adm.subject_id = icu.subject_id AND adm.hadm_id = icu.hadm_id
    WHERE
        p.gender = 'F'
        AND p.anchor_age BETWEEN 35 AND 45
),
combined_results AS ( -- New CTE to combine the two parts of the analysis
    -- Part 1: Mean +/- SD LOS by survival status
    SELECT
        CASE
            WHEN t.hospital_expire_flag = 0 THEN 'Discharged Alive'
            WHEN t.hospital_expire_flag = 1 THEN 'In-Hospital Death'
            ELSE 'Unknown' -- Should not occur with hospital_expire_flag
        END AS analysis_category,
        ROUND(AVG(t.los), 2) AS mean_los_days,
        ROUND(STDDEV(t.los), 2) AS stddev_los_days,
        CAST(NULL AS BIGNUMERIC) AS percent_los_lt_7_days
    FROM
        cohort_data t
    GROUP BY
        t.hospital_expire_flag

    UNION ALL

    -- Part 2: Percentage with LOS < 7 days for the overall cohort
    SELECT
        'Overall Cohort (LOS < 7 days %)' AS analysis_category,
        CAST(NULL AS BIGNUMERIC) AS mean_los_days,
        CAST(NULL AS BIGNUMERIC) AS stddev_los_days,
        ROUND(COUNTIF(t.los < 7) * 100.0 / COUNT(t.los), 2) AS percent_los_lt_7_days
    FROM
        cohort_data t
)
-- Final SELECT to order the combined results
SELECT *
FROM combined_results
ORDER BY
    CASE
        WHEN analysis_category = 'Discharged Alive' THEN 1
        WHEN analysis_category = 'In-Hospital Death' THEN 2
        WHEN analysis_category = 'Overall Cohort (LOS < 7 days %)' THEN 3
        ELSE 4
    END;