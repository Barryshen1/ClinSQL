WITH patient_cohort AS (
    -- Male patients aged 70-80 at admission
    SELECT 
        p.subject_id, 
        p.anchor_age,
        a.hadm_id,
        a.hospital_expire_flag
    FROM `physionet-data.mimiciv_3_1_hosp.patients` p
    INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a
        ON p.subject_id = a.subject_id
    WHERE p.gender = 'M'
        AND p.anchor_age BETWEEN 70 AND 80
),

icu_stays AS (
    -- ICU stays for the cohort
    SELECT 
        i.subject_id,
        i.hadm_id,
        i.stay_id,
        i.intime,
        i.outtime,
        i.los AS icu_los
    FROM `physionet-data.mimiciv_3_1_icu.icustays` i
    INNER JOIN patient_cohort pc
        ON i.subject_id = pc.subject_id
        AND i.hadm_id = pc.hadm_id
),

rrt_patients AS (
    -- Identify patients with RRT during hospitalization (ICD-10 or procedureevents)
    SELECT 
        pc.subject_id,
        pc.hadm_id,
        1 AS has_rrt
    FROM patient_cohort pc
    WHERE EXISTS (
        SELECT 1
        FROM `physionet-data.mimiciv_3_1_hosp.procedures_icd` picd
        WHERE picd.subject_id = pc.subject_id
            AND picd.hadm_id = pc.hadm_id
            AND (picd.icd_code LIKE '5A1D%' OR picd.icd_code LIKE '5A1C%')  -- Hemodialysis and peritoneal dialysis
    ) OR EXISTS (
        SELECT 1
        FROM `physionet-data.mimiciv_3_1_icu.procedureevents` pe
        WHERE pe.subject_id = pc.subject_id
            AND pe.hadm_id = pc.hadm_id
            AND pe.itemid IN (225802, 225803, 225809)  -- CRRT itemids
    )
),

vitals_first_48h AS (
    -- Extract MAP and HR events in first 48h of ICU stay
    SELECT 
        i.stay_id,
        ce.charttime,
        CASE WHEN ce.itemid = 220181 AND ce.valuenum < 65 THEN 1 ELSE 0 END AS hypotension,
        CASE WHEN ce.itemid = 220045 AND ce.valuenum > 100 THEN 1 ELSE 0 END AS tachycardia
    FROM icu_stays i
    INNER JOIN `physionet-data.mimiciv_3_1_icu.chartevents` ce
        ON i.stay_id = ce.stay_id
    WHERE ce.itemid IN (220181, 220045)  -- MAP and HR
        AND ce.charttime BETWEEN i.intime AND DATETIME_ADD(i.intime, INTERVAL 48 HOUR)
        AND ce.valuenum IS NOT NULL
),

composite_score_per_stay AS (
    -- Calculate composite score per stay: sum of hypotension and tachycardia events
    SELECT 
        stay_id,
        SUM(hypotension) AS hypotension_episodes,
        SUM(tachycardia) AS tachycardia_episodes,
        SUM(hypotension) + SUM(tachycardia) AS composite_score
    FROM vitals_first_48h
    GROUP BY stay_id
),

rrt_stays AS (
    -- ICU stays with RRT
    SELECT 
        i.*,
        cs.hypotension_episodes,
        cs.tachycardia_episodes,
        cs.composite_score,
        pc.hospital_expire_flag
    FROM icu_stays i
    INNER JOIN rrt_patients rrt
        ON i.subject_id = rrt.subject_id
        AND i.hadm_id = rrt.hadm_id
    INNER JOIN composite_score_per_stay cs
        ON i.stay_id = cs.stay_id
    INNER JOIN patient_cohort pc
        ON i.subject_id = pc.subject_id
        AND i.hadm_id = pc.hadm_id
),

rrt_90th_percentile AS (
    -- Compute the 90th percentile of composite score for RRT group
    SELECT 
        APPROX_QUANTILES(composite_score, 100)[OFFSET(90)] AS p90_score
    FROM rrt_stays
),

top_decile_rrt AS (
    -- RRT stays in the top decile
    SELECT 
        *,
        'RRT_top_decile' AS group_label
    FROM rrt_stays
    WHERE composite_score >= (SELECT p90_score FROM rrt_90th_percentile)
),

non_rrt_stays AS (
    -- ICU stays without RRT
    SELECT 
        i.*,
        cs.hypotension_episodes,
        cs.tachycardia_episodes,
        cs.composite_score,
        pc.hospital_expire_flag,
        'non_RRT' AS group_label
    FROM icu_stays i
    LEFT JOIN rrt_patients rrt
        ON i.subject_id = rrt.subject_id
        AND i.hadm_id = rrt.hadm_id
    INNER JOIN composite_score_per_stay cs
        ON i.stay_id = cs.stay_id
    INNER JOIN patient_cohort pc
        ON i.subject_id = pc.subject_id
        AND i.hadm_id = pc.hadm_id
    WHERE rrt.subject_id IS NULL
),

comparison_groups AS (
    -- Combine top decile RRT and non-RRT
    SELECT * FROM top_decile_rrt
    UNION ALL
    SELECT * FROM non_rrt_stays
)

-- Final comparison: for each group, aggregate the metrics
SELECT 
    group_label,
    COUNT(*) AS num_stays,
    AVG(hypotension_episodes) AS avg_hypotension_episodes,
    AVG(tachycardia_episodes) AS avg_tachycardia_episodes,
    AVG(icu_los) AS avg_icu_los,
    SUM(hospital_expire_flag) AS mortality_count,
    AVG(hospital_expire_flag) AS mortality_rate
FROM comparison_groups
GROUP BY group_label;