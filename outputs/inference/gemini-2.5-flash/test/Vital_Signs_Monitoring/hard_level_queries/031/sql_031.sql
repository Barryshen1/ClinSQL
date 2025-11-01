WITH admission_icu_info AS (
    -- Base information for all ICU stays, linked to patient demographics and admission outcomes
    SELECT
        a.subject_id,
        a.hadm_id,
        ie.stay_id,
        p.gender,
        p.anchor_age,
        ie.los,
        a.hospital_expire_flag,
        ie.intime,
        ie.outtime
    FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
    INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
        ON a.subject_id = p.subject_id
    INNER JOIN `physionet-data.mimiciv_3_1_icu.icustays` ie
        ON a.hadm_id = ie.hadm_id AND a.subject_id = ie.subject_id
),
post_op_hadm_ids AS (
    -- Identify hospital admissions with at least one procedure, broadly defined as "post-op"
    SELECT DISTINCT hadm_id
    FROM `physionet-data.mimiciv_3_1_hosp.procedures_icd`
),
all_post_op_icu_patients AS (
    -- Combine ICU stay info with post-op identification
    SELECT
        ai.subject_id,
        ai.hadm_id,
        ai.stay_id,
        ai.gender,
        ai.anchor_age,
        ai.los,
        ai.hospital_expire_flag,
        ai.intime,
        ai.outtime
    FROM admission_icu_info ai
    INNER JOIN post_op_hadm_ids ph
        ON ai.hadm_id = ph.hadm_id
),
vital_measurements AS (
    -- Extract relevant vital sign measurements within ICU stays
    SELECT
        ce.stay_id,
        ce.charttime,
        ce.itemid,
        ce.valuenum
    FROM `physionet-data.mimiciv_3_1_icu.chartevents` ce
    WHERE ce.itemid IN (
        220045, -- Heart Rate, label: "Heart Rate"
        220210, -- Respiratory Rate, label: "Respiratory Rate"
        220050, -- Arterial Blood Pressure systolic, label: "Art BP Systolic"
        223761, -- Temperature Celsius, label: "Temperature C"
        220277  -- O2 Saturation Pulseoxymetry, label: "O2 Saturation SpO2"
    )
    AND ce.valuenum IS NOT NULL
),
vital_flags AS (
    -- Flag each charttime for instability or specific outcome events
    SELECT
        vm.stay_id,
        vm.charttime,
        -- Flag for instability score (any deviation from normal ranges)
        MAX(CASE
            WHEN vm.itemid = 220045 AND (vm.valuenum < 60 OR vm.valuenum > 100) THEN 1 -- HR
            WHEN vm.itemid = 220210 AND (vm.valuenum < 12 OR vm.valuenum > 20) THEN 1 -- RR
            WHEN vm.itemid = 220050 AND (vm.valuenum < 90 OR vm.valuenum > 140) THEN 1 -- SBP
            WHEN vm.itemid = 223761 AND (vm.valuenum < 36 OR vm.valuenum > 37.5) THEN 1 -- Temp C
            WHEN vm.itemid = 220277 AND vm.valuenum < 90 THEN 1 -- SpO2
            ELSE 0
        END) AS is_unstable_moment,
        -- Flags for specific outcome event counts (question-specific thresholds)
        MAX(CASE WHEN vm.itemid = 223761 AND vm.valuenum > 38.5 THEN 1 ELSE 0 END) AS is_fever_event, -- Fever >38.5°C
        MAX(CASE WHEN vm.itemid = 220277 AND vm.valuenum < 90 THEN 1 ELSE 0 END) AS is_spo2_low_event, -- SpO2 <90%
        MAX(CASE WHEN vm.itemid = 220210 AND vm.valuenum > 20 THEN 1 ELSE 0 END) AS is_rr_high_event -- RR >20
    FROM vital_measurements vm
    GROUP BY vm.stay_id, vm.charttime
),
calculated_scores_and_events AS (
    -- Aggregate flags to get total instability score and episodic counts per stay
    SELECT
        vf.stay_id,
        SUM(vf.is_unstable_moment) AS instability_score, -- Count of distinct charttimes with at least one unstable vital
        SUM(vf.is_fever_event) AS fever_episodes,
        SUM(vf.is_spo2_low_event) AS spo2_low_episodes,
        SUM(vf.is_rr_high_event) AS rr_high_episodes
    FROM vital_flags vf
    GROUP BY vf.stay_id
),
patient_data_with_scores AS (
    -- Combine post-op ICU patient data with their calculated scores and events
    SELECT
        app.*,
        COALESCE(cse.instability_score, 0) AS instability_score,
        COALESCE(cse.fever_episodes, 0) AS fever_episodes,
        COALESCE(cse.spo2_low_episodes, 0) AS spo2_low_episodes,
        COALESCE(cse.rr_high_episodes, 0) AS rr_high_episodes
    FROM all_post_op_icu_patients app
    LEFT JOIN calculated_scores_and_events cse
        ON app.stay_id = cse.stay_id
),
target_demographic_ranked AS (
    -- Filter for the specific demographic and rank by instability score to find the top quartile
    SELECT
        pdws.*,
        -- NTILE is applied once for the specific demographic group to determine top quartile
        NTILE(4) OVER (ORDER BY pdws.instability_score DESC) AS instability_quartile
    FROM patient_data_with_scores pdws
    WHERE
        pdws.gender = 'M'
        AND pdws.anchor_age BETWEEN 63 AND 73
),
final_cohort_assignment AS (
    -- Classify each post-op patient into the target group or comparison group
    SELECT
        pdws.stay_id,
        pdws.instability_score,
        pdws.los,
        pdws.hospital_expire_flag,
        pdws.fever_episodes,
        pdws.spo2_low_episodes,
        pdws.rr_high_episodes,
        CASE
            WHEN tdr.stay_id IS NOT NULL AND tdr.instability_quartile = 1 THEN 'Target Group'
            ELSE 'Other Post-op Patients'
        END AS cohort_group
    FROM patient_data_with_scores pdws
    LEFT JOIN target_demographic_ranked tdr
        ON pdws.stay_id = tdr.stay_id
)
-- First part of UNION ALL: Target Group (A 68-year-old male is within 63-73 age range)
SELECT
    'Target Group' AS cohort_description,
    -- Calculate 95th percentile instability score for this specific group
    PERCENTILE_CONT(instability_score, 0.95) OVER () AS instability_score_95th_percentile, -- Fix applied here
    ROUND(CAST(AVG(fever_episodes) AS BIGNUMERIC), 2) AS avg_fever_episodes,
    ROUND(CAST(AVG(spo2_low_episodes) AS BIGNUMERIC), 2) AS avg_spo2_low_episodes,
    ROUND(CAST(AVG(rr_high_episodes) AS BIGNUMERIC), 2) AS avg_rr_high_episodes,
    ROUND(CAST(AVG(los) AS BIGNUMERIC), 2) AS avg_icu_los_days,
    ROUND(CAST(AVG(hospital_expire_flag) AS BIGNUMERIC), 4) AS mortality_rate
FROM final_cohort_assignment
WHERE cohort_group = 'Target Group'

UNION ALL

-- Second part of UNION ALL: Other Post-op Patients (comparison group)
SELECT
    'Other Post-op Patients' AS cohort_description,
    NULL AS instability_score_95th_percentile, -- Not applicable/requested for this group
    ROUND(CAST(AVG(fever_episodes) AS BIGNUMERIC), 2) AS avg_fever_episodes,
    ROUND(CAST(AVG(spo2_low_episodes) AS BIGNUMERIC), 2) AS avg_spo2_low_episodes,
    ROUND(CAST(AVG(rr_high_episodes) AS BIGNUMERIC), 2) AS avg_rr_high_episodes,
    ROUND(CAST(AVG(los) AS BIGNUMERIC), 2) AS avg_icu_los_days,
    ROUND(CAST(AVG(hospital_expire_flag) AS BIGNUMERIC), 4) AS mortality_rate
FROM final_cohort_assignment
WHERE cohort_group = 'Other Post-op Patients';