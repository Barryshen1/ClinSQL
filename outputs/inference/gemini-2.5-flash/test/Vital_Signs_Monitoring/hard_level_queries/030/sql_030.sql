WITH cohort_patients AS (
    SELECT
        adm.subject_id,
        adm.hadm_id,
        icu.stay_id,
        icu.intime,
        icu.outtime,
        -- Calculate age at admission using anchor_age and anchor_year
        (pat.anchor_age + (EXTRACT(YEAR FROM adm.admittime) - pat.anchor_year)) AS age_at_admission,
        adm.hospital_expire_flag,
        icu.los AS icu_los
    FROM `physionet-data.mimiciv_3_1_hosp.admissions` adm
    JOIN `physionet-data.mimiciv_3_1_hosp.patients` pat
        ON adm.subject_id = pat.subject_id
    JOIN `physionet-data.mimiciv_3_1_icu.icustays` icu
        ON adm.hadm_id = icu.hadm_id AND adm.subject_id = icu.subject_id
    WHERE
        pat.gender = 'F'
        AND (pat.anchor_age + (EXTRACT(YEAR FROM adm.admittime) - pat.anchor_year)) BETWEEN 43 AND 53
        -- Check for acute respiratory failure diagnosis (ICD-9: 518.81, ICD-10: J96.0x)
        AND EXISTS (
            SELECT 1
            FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` dign
            WHERE
                dign.subject_id = adm.subject_id
                AND dign.hadm_id = adm.hadm_id
                AND (
                    (dign.icd_version = 9 AND dign.icd_code LIKE '51881%')
                    OR (dign.icd_version = 10 AND dign.icd_code LIKE 'J960%')
                )
        )
),
-- Step 2: Extract relevant vital signs for the cohort in their first 48 hours in ICU
vitals_raw AS (
    SELECT
        cp.stay_id,
        -- Group by discrete hourly intervals
        DATETIME_DIFF(ce.charttime, cp.intime, HOUR) AS hour_offset,
        MAX(CASE WHEN ce.itemid = 220052 AND ce.valuenum IS NOT NULL THEN ce.valuenum ELSE NULL END) AS map, -- Mean Arterial Pressure
        MAX(CASE WHEN ce.itemid = 220045 AND ce.valuenum IS NOT NULL THEN ce.valuenum ELSE NULL END) AS hr,  -- Heart Rate
        MAX(CASE WHEN ce.itemid = 220210 AND ce.valuenum IS NOT NULL THEN ce.valuenum ELSE NULL END) AS rr,  -- Respiratory Rate
        MAX(CASE WHEN ce.itemid = 220277 AND ce.valuenum IS NOT NULL THEN ce.valuenum ELSE NULL END) AS spo2, -- SpO2
        MAX(CASE WHEN ce.itemid = 223762 AND ce.valuenum IS NOT NULL THEN ce.valuenum ELSE NULL END) AS temp_c -- Temperature Celsius
    FROM cohort_patients cp
    JOIN `physionet-data.mimiciv_3_1_icu.chartevents` ce
        ON cp.stay_id = ce.stay_id
    WHERE
        ce.itemid IN (220052, 220045, 220210, 220277, 223762)
        AND ce.valuenum IS NOT NULL
        AND ce.charttime >= cp.intime
        AND ce.charttime < DATETIME_ADD(cp.intime, INTERVAL 48 HOUR)
    GROUP BY
        cp.stay_id,
        hour_offset -- Group by discrete hourly offset from intime
),
-- Step 3: Determine hourly vital sign abnormality status for the cohort, and specific comparison flags
vitals_hourly_status AS (
    SELECT
        stay_id,
        hour_offset, -- Use hour_offset for hourly aggregation
        -- Vital Instability Index components (0 or 1 for abnormal)
        COALESCE(MAX(CASE WHEN map < 65 OR map > 100 THEN 1 ELSE 0 END), 0) AS map_abnormal,
        COALESCE(MAX(CASE WHEN hr < 50 OR hr > 100 THEN 1 ELSE 0 END), 0) AS hr_abnormal,
        COALESCE(MAX(CASE WHEN rr < 12 OR rr > 20 THEN 1 ELSE 0 END), 0) AS rr_abnormal,
        COALESCE(MAX(CASE WHEN spo2 < 90 THEN 1 ELSE 0 END), 0) AS spo2_abnormal, -- Only low SpO2 is considered abnormal for instability
        COALESCE(MAX(CASE WHEN temp_c < 36.0 OR temp_c > 38.0 THEN 1 ELSE 0 END), 0) AS temp_c_abnormal,
        -- Specific comparison flags (distinct from Vii definition)
        COALESCE(MAX(CASE WHEN map < 65 THEN 1 ELSE 0 END), 0) AS map_hypotensive_episode_flag,
        COALESCE(MAX(CASE WHEN hr > 100 THEN 1 ELSE 0 END), 0) AS hr_tachycardia_episode_flag
    FROM vitals_raw
    GROUP BY stay_id, hour_offset -- Group by discrete hourly offset from intime
),
-- Step 4: Calculate Vital Instability Index (Vii) and comparison metrics per stay for the cohort
cohort_vitals_summary AS (
    SELECT
        hs.stay_id,
        -- Vii: Maximum number of concurrently abnormal vital signs in any 1-hour window
        MAX(hs.map_abnormal + hs.hr_abnormal + hs.rr_abnormal + hs.spo2_abnormal + hs.temp_c_abnormal) AS vital_instability_index,
        -- Count of 1-hour periods with specific conditions
        SUM(hs.map_hypotensive_episode_flag) AS map_hypotension_episodes_count,
        SUM(hs.hr_tachycardia_episode_flag) AS hr_tachycardia_episodes_count
    FROM vitals_hourly_status hs
    GROUP BY hs.stay_id
),
-- Step 5: Merge Vii and original cohort data, and calculate quartiles
cohort_with_vii AS (
    SELECT
        cp.subject_id,
        cp.hadm_id,
        cp.stay_id,
        cp.hospital_expire_flag,
        cp.icu_los,
        COALESCE(cvs.vital_instability_index, 0) AS vital_instability_index, -- Assign 0 if no vital events reported
        COALESCE(cvs.map_hypotension_episodes_count, 0) AS map_hypotension_episodes_count,
        COALESCE(cvs.hr_tachycardia_episodes_count, 0) AS hr_tachycardia_episodes_count,
        NTILE(4) OVER (ORDER BY COALESCE(cvs.vital_instability_index, 0) DESC) AS vii_quartile -- 1 is top quartile (highest Vii)
    FROM cohort_patients cp
    LEFT JOIN cohort_vitals_summary cvs
        ON cp.stay_id = cvs.stay_id
),
-- Step 6: Define General ICU Population for comparison
general_icu_patients AS (
    SELECT
        icu.subject_id,
        icu.hadm_id,
        icu.stay_id,
        icu.intime,
        icu.outtime,
        adm.hospital_expire_flag,
        icu.los AS icu_los
    FROM `physionet-data.mimiciv_3_1_icu.icustays` icu
    JOIN `physionet-data.mimiciv_3_1_hosp.admissions` adm
        ON icu.hadm_id = adm.hadm_id AND icu.subject_id = adm.subject_id
),
-- Step 7: Extract relevant vital signs for GENERAL ICU population in their first 48 hours for comparison
general_vitals_raw AS (
    SELECT
        gip.stay_id,
        DATETIME_DIFF(ce.charttime, gip.intime, HOUR) AS hour_offset,
        MAX(CASE WHEN ce.itemid = 220052 AND ce.valuenum IS NOT NULL THEN ce.valuenum ELSE NULL END) AS map,
        MAX(CASE WHEN ce.itemid = 220045 AND ce.valuenum IS NOT NULL THEN ce.valuenum ELSE NULL END) AS hr
    FROM general_icu_patients gip
    JOIN `physionet-data.mimiciv_3_1_icu.chartevents` ce
        ON gip.stay_id = ce.stay_id
    WHERE
        ce.itemid IN (220052, 220045) -- Only MAP and HR needed for general comparison
        AND ce.valuenum IS NOT NULL
        AND ce.charttime >= gip.intime
        AND ce.charttime < DATETIME_ADD(gip.intime, INTERVAL 48 HOUR)
    GROUP BY
        gip.stay_id,
        hour_offset
),
-- Step 8: Determine hourly specific comparison flags for GENERAL ICU population
general_vitals_hourly_status AS (
    SELECT
        stay_id,
        hour_offset,
        COALESCE(MAX(CASE WHEN map < 65 THEN 1 ELSE 0 END), 0) AS map_hypotensive_episode_flag,
        COALESCE(MAX(CASE WHEN hr > 100 THEN 1 ELSE 0 END), 0) AS hr_tachycardia_episode_flag
    FROM general_vitals_raw
    GROUP BY stay_id, hour_offset
),
-- Step 9: Calculate comparison metrics for GENERAL ICU population per stay
general_icu_comparison_metrics AS (
    SELECT
        hs.stay_id,
        SUM(hs.map_hypotensive_episode_flag) AS map_hypotension_episodes_count,
        SUM(hs.hr_tachycardia_episode_flag) AS hr_tachycardia_episodes_count
    FROM general_vitals_hourly_status hs
    GROUP BY hs.stay_id
),
-- Step 10: Merge general ICU metrics with patient info
general_icu_with_metrics AS (
    SELECT
        gip.subject_id,
        gip.hadm_id,
        gip.stay_id,
        gip.hospital_expire_flag,
        gip.icu_los,
        COALESCE(gicm.map_hypotension_episodes_count, 0) AS map_hypotension_episodes_count,
        COALESCE(gicm.hr_tachycardia_episodes_count, 0) AS hr_tachycardia_episodes_count
    FROM general_icu_patients gip
    LEFT JOIN general_icu_comparison_metrics gicm
        ON gip.stay_id = gicm.stay_id
)

-- Final Results:
-- 1. 95th-percentile Vital Instability Index for the overall cohort
SELECT
    'Overall Cohort (Acute Respiratory Failure)' AS group_name,
    APPROX_QUANTILES(cqv.vital_instability_index, 100)[OFFSET(95)] AS p95_vital_instability_index, -- FIX: Using APPROX_QUANTILES for BigQuery compatibility.
    NULL AS avg_map_hypotension_episodes,
    NULL AS avg_hr_tachycardia_episodes,
    NULL AS avg_icu_los,
    NULL AS mortality_rate,
    COUNT(DISTINCT cqv.stay_id) AS num_stays
FROM cohort_with_vii cqv

UNION ALL

-- 2. Comparison metrics for the top quartile of the cohort (highest Vii)
SELECT
    'Cohort Top Quartile Vii' AS group_name,
    NULL AS p95_vital_instability_index, -- Not applicable here
    AVG(cqv.map_hypotension_episodes_count) AS avg_map_hypotension_episodes,
    AVG(cqv.hr_tachycardia_episodes_count) AS avg_hr_tachycardia_episodes,
    AVG(cqv.icu_los) AS avg_icu_los,
    AVG(cqv.hospital_expire_flag) AS mortality_rate,
    COUNT(DISTINCT cqv.stay_id) AS num_stays
FROM cohort_with_vii cqv
WHERE cqv.vii_quartile = 1

UNION ALL

-- 3. Comparison metrics for the general ICU population
SELECT
    'General ICU Population' AS group_name,
    NULL AS p95_vital_instability_index, -- Not applicable here
    AVG(gwim.map_hypotension_episodes_count) AS avg_map_hypotension_episodes,
    AVG(gwim.hr_tachycardia_episodes_count) AS avg_hr_tachycardia_episodes,
    AVG(gwim.icu_los) AS avg_icu_los,
    AVG(gwim.hospital_expire_flag) AS mortality_rate,
    COUNT(DISTINCT gwim.stay_id) AS num_stays
FROM general_icu_with_metrics gwim;