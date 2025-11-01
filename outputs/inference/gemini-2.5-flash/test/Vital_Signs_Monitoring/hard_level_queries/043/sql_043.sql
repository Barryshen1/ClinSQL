WITH respiratory_failure_admissions AS (
    -- Identify hospital admissions with a primary or secondary diagnosis of respiratory failure
    SELECT DISTINCT hadm_id
    FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd`
    WHERE
        -- ICD-9 codes for respiratory failure
        (icd_version = 9 AND icd_code IN ('51881', '51883', '51884'))
        -- ICD-10 codes for respiratory failure (starting with J96)
        OR (icd_version = 10 AND icd_code LIKE 'J96%')
),
cohort_all_rf AS (
    -- Base cohort: All ICU stays for patients with respiratory failure
    SELECT
        ie.subject_id,
        ie.hadm_id,
        ie.stay_id,
        ie.intime,
        ie.outtime,
        adm.hospital_expire_flag,
        pat.gender,
        pat.anchor_age,
        -- Calculate ICU length of stay in days
        TIMESTAMP_DIFF(ie.outtime, ie.intime, HOUR) / 24.0 AS icu_los_days
    FROM `physionet-data.mimiciv_3_1_icu.icustays` ie
    INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` adm
        ON ie.subject_id = adm.subject_id AND ie.hadm_id = adm.hadm_id
    INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` pat
        ON ie.subject_id = pat.subject_id
    INNER JOIN respiratory_failure_admissions rf_adm
        ON ie.hadm_id = rf_adm.hadm_id
    WHERE ie.intime IS NOT NULL AND ie.outtime IS NOT NULL
),
cohort_target_group AS (
    -- Target Group: Male ICU patients aged 40-50 with respiratory failure
    SELECT *
    FROM cohort_all_rf
    WHERE gender = 'M' AND anchor_age BETWEEN 40 AND 50
),
first_48hr_vitals AS (
    -- Extract relevant vital signs for ALL identified respiratory failure ICU stays
    -- within the first 48 hours since ICU intime.
    SELECT
        ce.subject_id,
        ce.hadm_id,
        arf.stay_id,
        ce.charttime,
        arf.intime AS icu_intime,
        CASE
            WHEN ce.itemid = 220045 THEN 'Heart Rate'
            WHEN ce.itemid = 220210 THEN 'Respiratory Rate'
            WHEN ce.itemid IN (220050, 220179, 223751) THEN 'Systolic Blood Pressure'
            WHEN ce.itemid IN (220052, 220181, 224639) THEN 'Mean Arterial Pressure'
            WHEN ce.itemid IN (223761, 223762) THEN 'Temperature' -- 223761 Fahrenheit, 223762 Celsius
            WHEN ce.itemid = 220277 THEN 'SPO2'
            ELSE NULL -- Should not happen with current itemid filter
        END AS vital_sign_name,
        -- Convert temperature to Celsius if recorded in Fahrenheit ItemID 223761
        CASE
            WHEN ce.itemid = 223761 AND ce.valuenum IS NOT NULL THEN (ce.valuenum - 32.0) * 5.0/9.0
            ELSE ce.valuenum
        END AS valuenum,
        ce.itemid
    FROM `physionet-data.mimiciv_3_1_icu.chartevents` ce
    INNER JOIN cohort_all_rf arf
        ON ce.subject_id = arf.subject_id AND ce.hadm_id = arf.hadm_id AND ce.stay_id = arf.stay_id
    WHERE
        ce.charttime BETWEEN arf.intime AND TIMESTAMP_ADD(arf.intime, INTERVAL 48 HOUR)
        AND ce.valuenum IS NOT NULL
        AND ce.itemid IN (
            220045, -- Heart Rate
            220210, -- Respiratory Rate
            220050, 220179, 223751, -- Systolic Blood Pressure (various sources)
            220052, 220181, 224639, -- Mean Arterial Pressure (various sources)
            223761, 223762, -- Temperature (Fahrenheit, Celsius)
            220277  -- SpO2
        )
        -- Filter out physiologically implausible values for data quality
        AND (
            (ce.itemid = 220045 AND ce.valuenum > 0 AND ce.valuenum < 300) OR -- HR
            (ce.itemid = 220210 AND ce.valuenum > 0 AND ce.valuenum < 70) OR  -- RR
            (ce.itemid IN (220050, 220179, 223751) AND ce.valuenum > 0 AND ce.valuenum < 300) OR -- SBP
            (ce.itemid IN (220052, 220181, 224639) AND ce.valuenum > 0 AND ce.valuenum < 200) OR -- MAP
            (ce.itemid IN (223761, 223762) AND ce.valuenum > 20 AND ce.valuenum < 45) OR -- Temp (assuming converted to Celsius, or in natural unit)
            (ce.itemid = 220277 AND ce.valuenum > 0 AND ce.valuenum <= 100)  -- SpO2
        )
),
vitals_with_flags AS (
    -- Assign flags for Vital Instability Index components, hypotension, and tachycardia
    SELECT
        fv.stay_id,
        fv.charttime,
        -- VII flags: 1 if abnormal, 0 if normal for a given vital sign
        CASE WHEN fv.vital_sign_name = 'Heart Rate' AND (fv.valuenum < 60 OR fv.valuenum > 100) THEN 1 ELSE 0 END AS vii_hr_flag,
        CASE WHEN fv.vital_sign_name = 'Respiratory Rate' AND (fv.valuenum < 12 OR fv.valuenum > 20) THEN 1 ELSE 0 END AS vii_rr_flag,
        CASE WHEN fv.vital_sign_name = 'Systolic Blood Pressure' AND (fv.valuenum < 90 OR fv.valuenum > 140) THEN 1 ELSE 0 END AS vii_sbp_flag,
        CASE WHEN fv.vital_sign_name = 'Temperature' AND (fv.valuenum < 36 OR fv.valuenum > 38) THEN 1 ELSE 0 END AS vii_temp_flag,
        CASE WHEN fv.vital_sign_name = 'SPO2' AND fv.valuenum < 92 THEN 1 ELSE 0 END AS vii_spo2_flag,
        -- Hypotension and Tachycardia flags for burden calculation
        CASE WHEN fv.vital_sign_name = 'Mean Arterial Pressure' AND fv.valuenum < 65 THEN 1 ELSE 0 END AS hypotensive_instance_flag,
        CASE WHEN fv.vital_sign_name = 'Mean Arterial Pressure' THEN 1 ELSE 0 END AS map_measurement_flag,
        CASE WHEN fv.vital_sign_name = 'Heart Rate' AND fv.valuenum > 100 THEN 1 ELSE 0 END AS tachycardic_instance_flag,
        CASE WHEN fv.vital_sign_name = 'Heart Rate' THEN 1 ELSE 0 END AS hr_measurement_flag
    FROM first_48hr_vitals fv
),
vii_burden_per_stay AS (
    -- Calculate instantaneous VII scores by summing flags at each charttime
    WITH instantaneous_scores AS (
        SELECT
            stay_id,
            charttime,
            -- Sum of abnormal vital signs at this specific charttime (instantaneous VII)
            SUM(vii_hr_flag + vii_rr_flag + vii_sbp_flag + vii_temp_flag + vii_spo2_flag) AS instantaneous_vii_score,
            SUM(hypotensive_instance_flag) AS hypotensive_instances_at_time,
            SUM(map_measurement_flag) AS map_measurements_at_time,
            SUM(tachycardic_instance_flag) AS tachycardic_instances_at_time,
            SUM(hr_measurement_flag) AS hr_measurements_at_time
        FROM vitals_with_flags
        GROUP BY stay_id, charttime
    )
    -- Aggregate across all charttimes for the 48-hour window for each stay_id
    SELECT
        iscores.stay_id,
        AVG(iscores.instantaneous_vii_score) AS avg_vii, -- Average of instantaneous VIIs over the 48 hours
        SAFE_DIVIDE(SUM(iscores.hypotensive_instances_at_time), SUM(iscores.map_measurements_at_time)) AS hypotensive_burden,
        SAFE_DIVIDE(SUM(iscores.tachycardic_instances_at_time), SUM(iscores.hr_measurements_at_time)) AS tachycardic_burden
    FROM instantaneous_scores iscores
    GROUP BY iscores.stay_id
)
-- Main query to present the requested statistics for both groups
SELECT
    'Target Group (Male, 40-50, RF)' AS group_name,
    COUNT(DISTINCT tg.stay_id) AS num_icu_stays,
    -- Vital Instability Index statistics for the target group
    STDDEV(vbs.avg_vii) AS vital_instability_index_sd,
    APPROX_QUANTILES(vbs.avg_vii, 100)[OFFSET(25)] AS vii_25th_percentile,
    APPROX_QUANTILES(vbs.avg_vii, 100)[OFFSET(50)] AS vii_50th_percentile,
    APPROX_QUANTILES(vbs.avg_vii, 100)[OFFSET(75)] AS vii_75th_percentile,
    APPROX_QUANTILES(vbs.avg_vii, 100)[OFFSET(95)] AS vii_95th_percentile,
    -- Burden, ICU LOS, and Mortality for the target group
    AVG(vbs.hypotensive_burden) AS avg_hypotensive_burden,
    AVG(vbs.tachycardic_burden) AS avg_tachycardic_burden,
    AVG(tg.icu_los_days) AS avg_icu_los_days,
    AVG(tg.hospital_expire_flag) AS mortality_rate -- Average of 0/1 gives the proportion/rate
FROM cohort_target_group tg
LEFT JOIN vii_burden_per_stay vbs
    ON tg.stay_id = vbs.stay_id
WHERE vbs.avg_vii IS NOT NULL -- Exclude stays where no valid vital signs were recorded for VII
GROUP BY 1
HAVING COUNT(DISTINCT tg.stay_id) > 0

UNION ALL

SELECT
    'All Respiratory Failure Patients' AS group_name,
    COUNT(DISTINCT arf.stay_id) AS num_icu_stays,
    -- VII statistics are not requested for the full cohort, so provide NULL
    NULL AS vital_instability_index_sd,
    NULL AS vii_25th_percentile,
    NULL AS vii_50th_percentile,
    NULL AS vii_75th_percentile,
    NULL AS vii_95th_percentile,
    -- Burden, ICU LOS, and Mortality for all respiratory failure patients
    AVG(vbs.hypotensive_burden) AS avg_hypotensive_burden,
    AVG(vbs.tachycardic_burden) AS avg_tachycardic_burden,
    AVG(arf.icu_los_days) AS avg_icu_los_days,
    AVG(arf.hospital_expire_flag) AS mortality_rate
FROM cohort_all_rf arf
LEFT JOIN vii_burden_per_stay vbs
    ON arf.stay_id = vbs.stay_id
WHERE (vbs.hypotensive_burden IS NOT NULL OR vbs.tachycardic_burden IS NOT NULL) -- Ensure at least some vital data for burden
GROUP BY 1
HAVING COUNT(DISTINCT arf.stay_id) > 0
ORDER BY group_name DESC;