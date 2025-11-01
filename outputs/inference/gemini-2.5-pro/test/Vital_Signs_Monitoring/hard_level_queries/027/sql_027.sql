WITH
-- 1. Identify all ICU stays for patients on Renal Replacement Therapy (RRT)
rrt_stays AS (
    SELECT DISTINCT stay_id
    FROM `physionet-data.mimiciv_3_1_icu.procedureevents`
    WHERE itemid IN (
        -- A comprehensive list of itemids for RRT from d_items
        225802, -- Dialysis - CRRT
        225803, -- Dialysis - CVVHD
        225805, -- Dialysis - CVVHDF
        224270, -- Dialysis Catheter
        225809, -- CVVHD
        225441, -- Hemodialysis
        225807  -- Dialysis - CVVH
    )
),

-- 2. Calculate hourly-averaged vital signs (MAP and HR) for RRT patients in the first 72h
hourly_vitals AS (
    SELECT
        ce.stay_id,
        DATETIME_TRUNC(ce.charttime, HOUR) AS hour_of_stay,
        -- Use AVG to get a single value for each vital in each hour bucket
        AVG(CASE WHEN ce.itemid IN (220052, 225312) THEN ce.valuenum ELSE NULL END) AS avg_map, -- Mean Arterial Pressure & Arterial BP Mean
        AVG(CASE WHEN ce.itemid = 220045 THEN ce.valuenum ELSE NULL END) AS avg_hr -- Heart Rate
    FROM `physionet-data.mimiciv_3_1_icu.chartevents` AS ce
    INNER JOIN `physionet-data.mimiciv_3_1_icu.icustays` AS icu
        ON ce.stay_id = icu.stay_id
    -- Filter to only include RRT patients
    WHERE ce.stay_id IN (SELECT stay_id FROM rrt_stays)
      AND ce.itemid IN (
        220052, -- Mean Arterial Pressure
        225312, -- Arterial BP Mean
        220045  -- Heart Rate
      )
      -- Filter for the first 72 hours of the ICU stay
      AND ce.charttime BETWEEN icu.intime AND DATETIME_ADD(icu.intime, INTERVAL 72 HOUR)
    GROUP BY
        ce.stay_id,
        hour_of_stay
),

-- 3. Calculate the vital-instability index: count of hours with concurrent MAP < 65 and HR > 100
instability_index AS (
    SELECT
        stay_id,
        COUNTIF(avg_map < 65 AND avg_hr > 100) AS unstable_hours
    FROM hourly_vitals
    GROUP BY stay_id
),

-- 4. Combine stay information, cohort definitions, and outcomes (LOS, mortality)
final_data AS (
    SELECT
        icu.stay_id,
        -- Define the two patient cohorts
        CASE
            WHEN p.gender = 'F' AND p.anchor_age BETWEEN 58 AND 68 THEN 'women_58_68'
            ELSE 'other_rrt_patients'
        END AS cohort,
        -- If a patient had no vital signs, their unstable hours count is 0
        COALESCE(ii.unstable_hours, 0) AS unstable_hours,
        icu.los,
        adm.hospital_expire_flag
    FROM `physionet-data.mimiciv_3_1_icu.icustays` AS icu
    -- Ensure we only consider RRT stays
    INNER JOIN rrt_stays ON icu.stay_id = rrt_stays.stay_id
    -- Join patient demographics to define cohorts
    INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` AS p
        ON icu.subject_id = p.subject_id
    -- Join admission info for hospital mortality
    INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` AS adm
        ON icu.hadm_id = adm.hadm_id
    -- Left join the instability index as some stays might not have vitals recorded
    LEFT JOIN instability_index AS ii
        ON icu.stay_id = ii.stay_id
)

-- Part 1: Report percentiles and IQR of the instability index for the target group
SELECT
    'percentiles_women_58_68' AS analysis_name,
    p[OFFSET(25)] AS unstable_hours_p25,
    p[OFFSET(50)] AS unstable_hours_p50_median,
    p[OFFSET(75)] AS unstable_hours_p75,
    p[OFFSET(90)] AS unstable_hours_p90,
    p[OFFSET(75)] - p[OFFSET(25)] AS unstable_hours_iqr,
    -- Fill other columns with NULL for a clean union
    CAST(NULL AS FLOAT64) AS avg_unstable_hours,
    CAST(NULL AS FLOAT64) AS avg_icu_los_days,
    CAST(NULL AS FLOAT64) AS mortality_rate
FROM (
    SELECT APPROX_QUANTILES(unstable_hours, 100) AS p
    FROM final_data
    WHERE cohort = 'women_58_68'
)

UNION ALL

-- Part 2: Report comparative metrics (avg instability, LOS, mortality) for both groups
SELECT
    cohort AS analysis_name,
    -- Fill percentile columns with NULL
    NULL,
    NULL,
    NULL,
    NULL,
    NULL,
    AVG(unstable_hours) AS avg_unstable_hours,
    AVG(los) AS avg_icu_los_days,
    AVG(CAST(hospital_expire_flag AS FLOAT64)) AS mortality_rate
FROM final_data
GROUP BY
    cohort
ORDER BY
    analysis_name;