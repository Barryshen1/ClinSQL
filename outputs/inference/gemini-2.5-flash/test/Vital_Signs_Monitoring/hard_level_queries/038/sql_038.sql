WITH icu_stays_cohort AS (
    -- Base cohort: get all ICU stays with patient demographics, admission info, and age at admission
    SELECT
        ic.subject_id,
        ic.hadm_id,
        ic.stay_id,
        ic.intime,
        ic.outtime,
        DATETIME_DIFF(ic.outtime, ic.intime, HOUR) AS icu_los_hours,
        p.gender,
        p.anchor_age + (EXTRACT(YEAR FROM adm.admittime) - p.anchor_year) AS age_at_admission,
        adm.hospital_expire_flag
    FROM
        `physionet-data.mimiciv_3_1_icu.icustays` AS ic
    INNER JOIN
        `physionet-data.mimiciv_3_1_hosp.admissions` AS adm
        ON ic.hadm_id = adm.hadm_id
    INNER JOIN
        `physionet-data.mimiciv_3_1_hosp.patients` AS p
        ON ic.subject_id = p.subject_id
),
se_diagnosis AS (
    -- Identify admissions with Status Epilepticus diagnosis
    SELECT DISTINCT
        d.subject_id,
        d.hadm_id
    FROM
        `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` AS d
    WHERE
        (d.icd_version = 9 AND d.icd_code LIKE '3452%') -- ICD-9 for Status Epilepticus (e.g., 34520, 34521)
        OR (d.icd_version = 10 AND d.icd_code LIKE 'G41%') -- ICD-10 for Epileptic Status (G41.x)
),
se_cohort AS (
    -- Combine base ICU cohort with status epilepticus flag
    SELECT
        icc.*,
        CASE WHEN se.hadm_id IS NOT NULL THEN 1 ELSE 0 END AS has_status_epilepticus
    FROM
        icu_stays_cohort AS icc
    LEFT JOIN
        se_diagnosis AS se
        ON icc.subject_id = se.subject_id AND icc.hadm_id = se.hadm_id
),
-- Extract vital signs (HR and preferred MAP) within the first 72 hours of ICU stay
vitals_hr AS (
    SELECT
        ce.stay_id,
        ce.charttime,
        ce.valuenum AS hr_value
    FROM
        `physionet-data.mimiciv_3_1_icu.chartevents` AS ce
    WHERE
        ce.itemid = 220045 -- Heart Rate (standard itemid)
        AND ce.valuenum IS NOT NULL
        AND ce.valuenum > 0
),
vitals_map_priority AS (
    -- Prioritize invasive MAP (220052) over non-invasive MAP (220181)
    SELECT
        ce.stay_id,
        ce.charttime,
        ce.valuenum AS map_value,
        ROW_NUMBER() OVER (PARTITION BY ce.stay_id, ce.charttime ORDER BY CASE WHEN ce.itemid = 220052 THEN 1 WHEN ce.itemid = 220181 THEN 2 ELSE 3 END ASC) as rn
    FROM
        `physionet-data.mimiciv_3_1_icu.chartevents` AS ce
    WHERE
        ce.itemid IN (220052, 220181) -- Arterial BP Mean, Non Invasive Blood Pressure mean
        AND ce.valuenum IS NOT NULL
        AND ce.valuenum > 0
),
vitals_map AS (
    SELECT stay_id, charttime, map_value
    FROM vitals_map_priority
    WHERE rn = 1
),
vitals_combined AS (
    -- Combine Heart Rate and preferred MAP values by charttime for each stay
    SELECT
        COALESCE(hr.stay_id, m.stay_id) AS stay_id,
        COALESCE(hr.charttime, m.charttime) AS charttime,
        hr.hr_value,
        m.map_value
    FROM
        vitals_hr AS hr
    FULL OUTER JOIN
        vitals_map AS m
        ON hr.stay_id = m.stay_id AND hr.charttime = m.charttime
    WHERE
        hr.hr_value IS NOT NULL OR m.map_value IS NOT NULL
),
vitals_4hr_windows AS (
    -- Calculate average HR and MAP in 4-hour windows within the first 72 hours
    SELECT
        s.stay_id,
        s.intime,
        -- Define 4-hour window start relative to icu_intime
        -- FIX: Cast interval value to INT64 as required by BigQuery's DATETIME_ADD
        DATETIME_ADD(s.intime, INTERVAL CAST((FLOOR(DATETIME_DIFF(vc.charttime, s.intime, HOUR) / 4)) * 4 AS INT64) HOUR) AS window_start,
        AVG(vc.hr_value) AS avg_hr_window,
        AVG(vc.map_value) AS avg_map_window,
        -- Count of readings in the window, to ensure the average is based on actual data
        COUNT(vc.hr_value) AS hr_readings_in_window,
        COUNT(vc.map_value) AS map_readings_in_window
    FROM
        se_cohort AS s
    INNER JOIN
        vitals_combined AS vc
        ON s.stay_id = vc.stay_id
    WHERE
        vc.charttime >= s.intime
        AND vc.charttime < DATETIME_ADD(s.intime, INTERVAL 72 HOUR)
    GROUP BY
        s.stay_id, s.intime,
        DATETIME_ADD(s.intime, INTERVAL CAST((FLOOR(DATETIME_DIFF(vc.charttime, s.intime, HOUR) / 4)) * 4 AS INT64) HOUR)
    HAVING
        -- FIX: Simplified HAVING clause - if count > 0, avg will not be null due to prior filtering
        COUNT(vc.hr_value) > 0 OR COUNT(vc.map_value) > 0
),
patient_vitals_summary AS (
    -- Summarize vital abnormalities per stay within the 72-hour window
    SELECT
        stay_id,
        COUNT(DISTINCT window_start) AS total_windows_with_data_72hr,
        SUM(CASE WHEN avg_hr_window > 100 THEN 1 ELSE 0 END) AS tachycardia_windows,
        SUM(CASE WHEN avg_map_window < 65 THEN 1 ELSE 0 END) AS map_low_windows,
        SUM(CASE WHEN (avg_hr_window > 100 OR avg_map_window < 65) THEN 1 ELSE 0 END) AS vital_instability_windows
    FROM
        vitals_4hr_windows
    GROUP BY
        stay_id
),
final_patient_data AS (
    -- Combine patient cohort data with vital summary and calculate burdens
    SELECT
        sc.subject_id,
        sc.hadm_id,
        sc.stay_id,
        sc.gender,
        sc.age_at_admission,
        sc.has_status_epilepticus,
        sc.icu_los_hours,
        sc.hospital_expire_flag,
        COALESCE(pvs.total_windows_with_data_72hr, 0) AS total_windows_with_data_72hr,
        COALESCE(pvs.tachycardia_windows, 0) AS tachycardia_windows,
        COALESCE(pvs.map_low_windows, 0) AS map_low_windows,
        COALESCE(pvs.vital_instability_windows, 0) AS vital_instability_windows,
        -- Calculate burdens as proportion of windows with data
        CASE WHEN COALESCE(pvs.total_windows_with_data_72hr, 0) > 0
             THEN SAFE_DIVIDE(CAST(pvs.tachycardia_windows AS BIGNUMERIC), pvs.total_windows_with_data_72hr)
             ELSE 0
        END AS tachycardia_burden,
        CASE WHEN COALESCE(pvs.total_windows_with_data_72hr, 0) > 0
             THEN SAFE_DIVIDE(CAST(pvs.map_low_windows AS BIGNUMERIC), pvs.total_windows_with_data_72hr)
             ELSE 0
        END AS map_low_burden,
        -- ADDED: Vital instability burden as a more appropriate "index"
        CASE WHEN COALESCE(pvs.total_windows_with_data_72hr, 0) > 0
             THEN SAFE_DIVIDE(CAST(pvs.vital_instability_windows AS BIGNUMERIC), pvs.total_windows_with_data_72hr)
             ELSE 0
        END AS vital_instability_burden
    FROM
        se_cohort AS sc
    LEFT JOIN
        patient_vitals_summary AS pvs
        ON sc.stay_id = pvs.stay_id
)
-- Calculate and present statistics for the specific cohort
, specific_cohort_stats AS (
    SELECT
        'Specific Cohort (Female, 63-73, Status Epilepticus)' AS cohort_name,
        COUNT(DISTINCT stay_id) AS num_icu_stays,
        -- FIX: Use vital_instability_burden for index and correct PERCENTILE_CONT aggregate syntax
        AVG(vital_instability_burden) AS mean_vital_instability_index,
        PERCENTILE_CONT(vital_instability_burden, 0.25) AS p25_vital_instability_index,
        PERCENTILE_CONT(vital_instability_burden, 0.50) AS p50_vital_instability_index,
        PERCENTILE_CONT(vital_instability_burden, 0.75) AS p75_vital_instability_index,
        PERCENTILE_CONT(vital_instability_burden, 0.90) AS p90_vital_instability_index,
        AVG(tachycardia_burden) * 100 AS mean_tachycardia_burden_percent,
        AVG(map_low_burden) * 100 AS mean_map_low_burden_percent,
        AVG(icu_los_hours) AS mean_icu_los_hours,
        -- FIX: Correct PERCENTILE_CONT aggregate syntax for icu_los_hours
        PERCENTILE_CONT(icu_los_hours, 0.25) AS p25_icu_los_hours,
        PERCENTILE_CONT(icu_los_hours, 0.50) AS p50_icu_los_hours,
        PERCENTILE_CONT(icu_los_hours, 0.75) AS p75_icu_los_hours,
        PERCENTILE_CONT(icu_los_hours, 0.90) AS p90_icu_los_hours,
        AVG(hospital_expire_flag) * 100 AS mortality_rate_percent
    FROM
        final_patient_data
    WHERE
        gender = 'F'
        AND age_at_admission BETWEEN 63 AND 73
        AND has_status_epilepticus = 1
)
-- Calculate and present statistics for the general ICU population
, general_icu_stats AS (
    SELECT
        'General ICU Population' AS cohort_name,
        COUNT(DISTINCT stay_id) AS num_icu_stays,
        -- FIX: Use vital_instability_burden for index and correct PERCENTILE_CONT aggregate syntax
        AVG(vital_instability_burden) AS mean_vital_instability_index,
        PERCENTILE_CONT(vital_instability_burden, 0.25) AS p25_vital_instability_index,
        PERCENTILE_CONT(vital_instability_burden, 0.50) AS p50_vital_instability_index,
        PERCENTILE_CONT(vital_instability_burden, 0.75) AS p75_vital_instability_index,
        PERCENTILE_CONT(vital_instability_burden, 0.90) AS p90_vital_instability_index,
        AVG(tachycardia_burden) * 100 AS mean_tachycardia_burden_percent,
        AVG(map_low_burden) * 100 AS mean_map_low_burden_percent,
        AVG(icu_los_hours) AS mean_icu_los_hours,
        -- FIX: Correct PERCENTILE_CONT aggregate syntax for icu_los_hours
        PERCENTILE_CONT(icu_los_hours, 0.25) AS p25_icu_los_hours,
        PERCENTILE_CONT(icu_los_hours, 0.50) AS p50_icu_los_hours,
        PERCENTILE_CONT(icu_los_hours, 0.75) AS p75_icu_los_hours,
        PERCENTILE_CONT(icu_los_hours, 0.90) AS p90_icu_los_hours,
        AVG(hospital_expire_flag) * 100 AS mortality_rate_percent
    FROM
        final_patient_data
)
-- Combine results from both cohorts
SELECT * FROM specific_cohort_stats
UNION ALL
SELECT * FROM general_icu_stats;