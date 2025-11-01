WITH patient_cohort AS (
    -- Step 1: Define the base cohort of male ICU patients aged 70-80
    SELECT
        p.subject_id,
        adm.hadm_id,
        icu.stay_id,
        p.gender,
        p.anchor_age,
        adm.admittime,
        icu.intime,
        icu.outtime,
        icu.los,
        adm.hospital_expire_flag
    FROM
        `physionet-data.mimiciv_3_1_hosp.patients` p
    INNER JOIN
        `physionet-data.mimiciv_3_1_hosp.admissions` adm
        ON p.subject_id = adm.subject_id
    INNER JOIN
        `physionet-data.mimiciv_3_1_icu.icustays` icu
        ON adm.hadm_id = icu.hadm_id
    WHERE
        p.gender = 'M'
        AND p.anchor_age BETWEEN 70 AND 80
),
rrt_patients AS (
    -- Step 2: Identify patients who received RRT during their ICU stay
    SELECT DISTINCT
        pc.subject_id,
        pc.hadm_id,
        pc.stay_id
    FROM
        patient_cohort pc
    INNER JOIN
        `physionet-data.mimiciv_3_1_icu.procedureevents` pe
        ON pc.stay_id = pe.stay_id
    WHERE
        pe.itemid IN (
            225725, -- CVVH
            225727, -- IHD (Intermittent Hemodialysis by label in d_items)
            225729, -- CRRT
            229129, -- Hemodialysis - Outpatient (often recorded even if inpatient)
            229131, -- CVVHF (Continuous Veno-Venous Hemofiltration)
            229132  -- Intermittent Hemodialysis
        )
        AND pe.starttime BETWEEN pc.intime AND pc.outtime -- Ensure RRT occurred during ICU stay
),
vital_signs_48hr AS (
    -- Step 3a: Extract vital signs (MAP, HR) for the first 48 hours of ICU stay
    SELECT
        pc.stay_id,
        ch.itemid,
        ch.valuenum
    FROM
        patient_cohort pc
    INNER JOIN
        `physionet-data.mimiciv_3_1_icu.chartevents` ch
        ON pc.stay_id = ch.stay_id
    WHERE
        ch.itemid IN (
            220052, -- Arterial Blood Pressure mean
            220045  -- Heart Rate
        )
        AND ch.charttime BETWEEN pc.intime AND DATETIME_ADD(pc.intime, INTERVAL 48 HOUR)
        AND ch.valuenum IS NOT NULL -- Exclude records without a valid numeric value
),
instability_score AS (
    -- Step 3b: Calculate 48-hour composite vital instability score
    SELECT
        vs.stay_id,
        SUM(CASE WHEN vs.itemid = 220052 AND vs.valuenum < 65 THEN 1 ELSE 0 END) AS hypotension_count_48hr,
        SUM(CASE WHEN vs.itemid = 220045 AND vs.valuenum > 100 THEN 1 ELSE 0 END) AS tachycardia_count_48hr,
        SUM(CASE WHEN vs.itemid = 220045 AND vs.valuenum < 50 THEN 1 ELSE 0 END) AS bradycardia_count_48hr,
        (SUM(CASE WHEN vs.itemid = 220052 AND vs.valuenum < 65 THEN 1 ELSE 0 END) +
         SUM(CASE WHEN vs.itemid = 220045 AND vs.valuenum > 100 THEN 1 ELSE 0 END) +
         SUM(CASE WHEN vs.itemid = 220045 AND vs.valuenum < 50 THEN 1 ELSE 0 END)) AS composite_instability_score_48hr
    FROM
        vital_signs_48hr vs
    GROUP BY
        vs.stay_id
),
rrt_with_score AS (
    -- Step 4a: Combine patient cohort with RRT status and 48hr instability score
    SELECT
        pc.subject_id,
        pc.hadm_id,
        pc.stay_id,
        pc.intime,
        pc.outtime,
        pc.los,
        pc.hospital_expire_flag,
        CASE WHEN rp.stay_id IS NOT NULL THEN 1 ELSE 0 END AS has_rrt_flag,
        COALESCE(isc.composite_instability_score_48hr, 0) AS instability_score_48hr_rrt -- Assign 0 if no vital data in first 48hr
    FROM
        patient_cohort pc
    LEFT JOIN
        rrt_patients rp
        ON pc.stay_id = rp.stay_id
    LEFT JOIN
        instability_score isc
        ON pc.stay_id = isc.stay_id
),
rrt_scores_percentiles AS (
    -- Step 4b: Calculate the 90th percentile of instability score for RRT patients
    SELECT
        stay_id,
        instability_score_48hr_rrt,
        -- FIX: Corrected PERCENTILE_CONT function signature
        PERCENTILE_CONT(instability_score_48hr_rrt, 0.9) OVER () AS p90_instability_score
    FROM
        rrt_with_score
    WHERE
        has_rrt_flag = 1
),
top_decile_rrt AS (
    -- Step 4c: Identify the top decile of RRT patients by instability score
    SELECT
        r.stay_id
    FROM
        rrt_scores_percentiles r
    WHERE
        r.instability_score_48hr_rrt >= r.p90_instability_score
),
final_cohort_classification AS (
    -- Step 5: Classify patients into comparison groups
    SELECT
        rws.subject_id,
        rws.hadm_id,
        rws.stay_id,
        rws.intime,
        rws.outtime,
        rws.los,
        rws.hospital_expire_flag,
        rws.has_rrt_flag,
        rws.instability_score_48hr_rrt,
        CASE
            WHEN td.stay_id IS NOT NULL THEN 'TOP_DECILE_RRT_GROUP'
            WHEN rws.has_rrt_flag = 0 THEN 'NO_RRT_GROUP'
            ELSE NULL -- Other RRT patients not in top decile are excluded from comparison
        END AS comparison_group
    FROM
        rrt_with_score rws
    LEFT JOIN
        top_decile_rrt td
        ON rws.stay_id = td.stay_id
    WHERE
        td.stay_id IS NOT NULL OR rws.has_rrt_flag = 0 -- Only include the two desired comparison groups
),
vital_signs_full_icu_stay AS (
    -- Step 6a: Extract vital signs (MAP, HR) for the entire ICU stay for comparison metrics, for the classified cohort
    SELECT
        fcc.stay_id,
        ch.itemid,
        ch.valuenum
    FROM
        final_cohort_classification fcc
    INNER JOIN
        `physionet-data.mimiciv_3_1_icu.chartevents` ch
        ON fcc.stay_id = ch.stay_id
    WHERE
        ch.itemid IN (
            220052, -- Arterial Blood Pressure mean
            220045  -- Heart Rate
        )
        AND ch.charttime BETWEEN fcc.intime AND fcc.outtime
        AND ch.valuenum IS NOT NULL
),
full_stay_metrics AS (
    -- Step 6b: Calculate full-stay vital sign metrics (hypotension, tachycardia episodes)
    SELECT
        vs.stay_id,
        SUM(CASE WHEN vs.itemid = 220052 AND vs.valuenum < 65 THEN 1 ELSE 0 END) AS hypotension_episodes,
        SUM(CASE WHEN vs.itemid = 220045 AND vs.valuenum > 100 THEN 1 ELSE 0 END) AS tachycardia_episodes
    FROM
        vital_signs_full_icu_stay vs
    GROUP BY
        vs.stay_id
)
-- Final comparison query
SELECT
    fcc.comparison_group,
    COUNT(DISTINCT fcc.stay_id) AS num_icu_stays,
    -- For RRT patients, show the 90th percentile score. For No RRT, display NULL or 0.
    MAX(CASE WHEN fcc.comparison_group = 'TOP_DECILE_RRT_GROUP' THEN rs.p90_instability_score ELSE NULL END) AS p90_instability_score_for_rrt_group,
    AVG(fcc.los) AS avg_icu_los_days,
    SUM(fcc.hospital_expire_flag) AS total_hospital_expire_count,
    AVG(fcc.hospital_expire_flag) * 100 AS hospital_expire_percentage,
    AVG(COALESCE(fsm.hypotension_episodes, 0)) AS avg_hypotension_episodes_per_stay,
    AVG(COALESCE(fsm.tachycardia_episodes, 0)) AS avg_tachycardia_episodes_per_stay
FROM
    final_cohort_classification fcc
LEFT JOIN
    full_stay_metrics fsm
    ON fcc.stay_id = fsm.stay_id
LEFT JOIN
    rrt_scores_percentiles rs
    ON fcc.stay_id = rs.stay_id -- Join to get the p90 value
WHERE
    fcc.comparison_group IS NOT NULL
GROUP BY
    fcc.comparison_group
ORDER BY
    fcc.comparison_group;