WITH first_stays AS (
    -- Pre-select and rank ICU stays to efficiently find the first one per hospital admission
    SELECT
        subject_id,
        hadm_id,
        stay_id,
        intime,
        outtime,
        los,
        ROW_NUMBER() OVER(PARTITION BY hadm_id ORDER BY intime) as rn
    FROM `physionet-data.mimiciv_3_1_icu.icustays`
),
icu_cohort AS (
    -- Step 1: Define the base cohort of male patients aged 70-80 on their first ICU stay per admission.
    SELECT
        p.subject_id,
        a.hadm_id,
        i.stay_id,
        DATETIME_DIFF(i.intime, DATETIME(p.anchor_year, 1, 1, 0, 0, 0), YEAR) + p.anchor_age AS age_at_icu_intime,
        i.intime,
        i.outtime,
        i.los,
        a.hospital_expire_flag
    FROM
        `physionet-data.mimiciv_3_1_hosp.patients` AS p
    INNER JOIN
        `physionet-data.mimiciv_3_1_hosp.admissions` AS a ON p.subject_id = a.subject_id
    INNER JOIN
        first_stays AS i ON a.hadm_id = i.hadm_id
    WHERE
        p.gender = 'M'
        AND i.rn = 1 -- Filter for the first ICU stay only
        AND DATETIME_DIFF(i.intime, DATETIME(p.anchor_year, 1, 1, 0, 0, 0), YEAR) + p.anchor_age BETWEEN 70 AND 80
),
rrt_stays AS (
    -- Step 2: Identify all ICU stays that involved Renal Replacement Therapy (RRT).
    SELECT DISTINCT stay_id
    FROM `physionet-data.mimiciv_3_1_icu.procedureevents`
    WHERE itemid IN (
        225802, -- Dialysis - CRRT
        225803, -- Dialysis - CVVHD
        225805, -- Dialysis - CVVHDF
        225441, -- Hemodialysis
        225809  -- Dialysis - CVVH
    )
),
hourly_grid AS (
    -- Step 3: Create a continuous hourly grid for the first 48 hours of each ICU stay.
    SELECT
        stay_id,
        hour_timestamp
    FROM
        icu_cohort
    CROSS JOIN
        UNNEST(GENERATE_TIMESTAMP_ARRAY(CAST(intime AS TIMESTAMP), TIMESTAMP_ADD(CAST(intime AS TIMESTAMP), INTERVAL 47 HOUR), INTERVAL 1 HOUR)) AS hour_timestamp
),
instability_metrics AS (
    -- Step 4: For each hour, determine the presence of hypotension, tachycardia, and use of life support.
    WITH hourly_vitals AS (
        -- Get hourly average MAP and HR
        SELECT
            ce.stay_id,
            TIMESTAMP_TRUNC(CAST(ce.charttime AS TIMESTAMP), HOUR) AS hour_timestamp,
            AVG(CASE WHEN ce.itemid = 220052 THEN ce.valuenum ELSE NULL END) as map, -- MAP (Invasive)
            AVG(CASE WHEN ce.itemid = 220045 THEN ce.valuenum ELSE NULL END) as hr  -- Heart Rate
        FROM `physionet-data.mimiciv_3_1_icu.chartevents` ce
        INNER JOIN icu_cohort ic ON ce.stay_id = ic.stay_id
        WHERE
            ce.charttime BETWEEN ic.intime AND DATETIME_ADD(ic.intime, INTERVAL 48 HOUR)
            AND ce.itemid IN (220052, 220045)
            AND ce.valuenum > 0
        GROUP BY ce.stay_id, TIMESTAMP_TRUNC(CAST(ce.charttime AS TIMESTAMP), HOUR)
    ),
    hourly_interventions AS (
        -- Determine which hours had vasopressor or ventilation support
        SELECT
            g.stay_id,
            g.hour_timestamp,
            MAX(CASE WHEN vaso.stay_id IS NOT NULL THEN 1 ELSE 0 END) AS on_vaso,
            MAX(CASE WHEN vent.stay_id IS NOT NULL THEN 1 ELSE 0 END) AS on_vent
        FROM hourly_grid g
        LEFT JOIN (
            -- Vasopressor infusions
            SELECT stay_id, starttime, endtime FROM `physionet-data.mimiciv_3_1_icu.inputevents`
            WHERE itemid IN (221906, 221289, 221749, 221662, 222315, 221653) AND statusdescription != 'Rewritten'
        ) AS vaso ON g.stay_id = vaso.stay_id AND g.hour_timestamp >= CAST(vaso.starttime AS TIMESTAMP) AND g.hour_timestamp < CAST(vaso.endtime AS TIMESTAMP)
        LEFT JOIN (
            -- Invasive ventilation
            SELECT stay_id, starttime, endtime FROM `physionet-data.mimiciv_3_1_icu.procedureevents`
            WHERE itemid = 225792 AND statusdescription != 'Rewritten'
        ) AS vent ON g.stay_id = vent.stay_id AND g.hour_timestamp >= CAST(vent.starttime AS TIMESTAMP) AND g.hour_timestamp < CAST(vent.endtime AS TIMESTAMP)
        GROUP BY g.stay_id, g.hour_timestamp
    )
    -- Combine vitals and interventions to calculate hourly points
    SELECT
        g.stay_id,
        g.hour_timestamp,
        CASE WHEN hv.map < 65 THEN 1 ELSE 0 END AS is_hypotensive,
        CASE WHEN hv.hr > 120 THEN 1 ELSE 0 END AS is_tachycardic,
        -- Calculate instability points for the score
        (CASE WHEN hv.map < 65 THEN 1 ELSE 0 END) +
        (CASE WHEN hv.hr > 120 THEN 1 ELSE 0 END) +
        (CASE WHEN hi.on_vaso = 1 THEN 2 ELSE 0 END) +
        (CASE WHEN hi.on_vent = 1 THEN 2 ELSE 0 END) AS instability_points
    FROM hourly_grid g
    LEFT JOIN hourly_vitals hv ON g.stay_id = hv.stay_id AND g.hour_timestamp = hv.hour_timestamp
    LEFT JOIN hourly_interventions hi ON g.stay_id = hi.stay_id AND g.hour_timestamp = hi.hour_timestamp
),
patient_scores AS (
    -- Step 5: Sum the hourly data to get a total 48-hour score for each patient.
    SELECT
        stay_id,
        SUM(is_hypotensive) AS hypotensive_hours,
        SUM(is_tachycardic) AS tachycardic_hours,
        SUM(instability_points) AS instability_score
    FROM instability_metrics
    GROUP BY stay_id
),
p90_rrt_score AS (
    -- Step 6: Calculate the 90th percentile of the instability score for the RRT group.
    SELECT
        APPROX_QUANTILES(s.instability_score, 100)[OFFSET(90)] AS p90_score
    FROM patient_scores s
    INNER JOIN rrt_stays r ON s.stay_id = r.stay_id
),
final_groups AS (
    -- Step 7: Assign each patient to a final analysis group: 'Top_Decile_RRT' or 'Control_No_RRT'.
    SELECT
        i.stay_id,
        i.los,
        i.hospital_expire_flag,
        s.hypotensive_hours,
        s.tachycardic_hours,
        CASE
            WHEN r.stay_id IS NOT NULL AND s.instability_score >= (SELECT p90_score FROM p90_rrt_score) THEN 'Top_Decile_RRT'
            WHEN r.stay_id IS NULL THEN 'Control_No_RRT'
            ELSE NULL -- RRT patients not in the top decile are excluded from this comparison
        END AS group_name
    FROM icu_cohort i
    LEFT JOIN patient_scores s ON i.stay_id = s.stay_id
    LEFT JOIN rrt_stays r ON i.stay_id = r.stay_id
)
-- Step 8: Perform the final aggregation to compare the two groups.
SELECT
    fg.group_name,
    COUNT(DISTINCT fg.stay_id) AS num_patients,
    -- For hypotension/tachycardia, we calculate the average proportion of the 48h period spent in that state.
    AVG(fg.hypotensive_hours / 48.0) AS avg_proportion_time_hypotensive_map_lt_65,
    AVG(fg.tachycardic_hours / 48.0) AS avg_proportion_time_tachycardic_hr_gt_120,
    AVG(fg.los) AS avg_icu_los_days,
    AVG(CAST(fg.hospital_expire_flag AS FLOAT64)) AS in_hospital_mortality_rate
FROM final_groups fg
WHERE fg.group_name IS NOT NULL
GROUP BY fg.group_name
ORDER BY fg.group_name;