WITH RRT_HADM_IDS AS (
    -- Identify all hospital admissions (hadm_id) where RRT was performed or indicated
    SELECT DISTINCT subject_id, hadm_id
    FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd`
    WHERE
        (icd_version = 9 AND icd_code IN ('3995', '3993', '3999')) OR
        (icd_version = 10 AND icd_code IN ('5A1D00Z', '5A1D60Z', '5A1E00Z', '5A1E30Z', '5A1G00Z', '5A1G30Z'))
    UNION DISTINCT
    SELECT DISTINCT subject_id, hadm_id
    FROM `physionet-data.mimiciv_3_1_hosp.procedures_icd`
    WHERE
        (icd_version = 9 AND icd_code IN ('3995', '3993', '3999')) OR
        (icd_version = 10 AND icd_code IN ('5A1D00Z', '5A1D60Z', '5A1E00Z', '5A1E30Z', '5A1G00Z', '5A1G30Z'))
),
ICU_RRT_STAYS AS (
    -- Get all ICU stays for RRT patients, along with patient demographics and admission info
    SELECT
        ie.subject_id,
        ie.hadm_id,
        ie.stay_id,
        ie.intime,
        ie.outtime,
        ie.los,
        p.gender,
        p.anchor_age,
        adm.hospital_expire_flag
    FROM `physionet-data.mimiciv_3_1_icu.icustays` AS ie
    INNER JOIN RRT_HADM_IDS AS rrt ON ie.subject_id = rrt.subject_id AND ie.hadm_id = rrt.hadm_id
    INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` AS p ON ie.subject_id = p.subject_id
    INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` AS adm ON ie.hadm_id = adm.hadm_id
),
TARGET_COHORT_DATA AS (
    -- Filter for the specific target group: female, 58-68 years old
    SELECT *
    FROM ICU_RRT_STAYS
    WHERE gender = 'F' AND anchor_age BETWEEN 58 AND 68
),
ALL_RRT_COHORT_DATA AS (
    -- All RRT ICU patients for comparison
    SELECT *
    FROM ICU_RRT_STAYS
),
HOURLY_VITALS_EXTRACTED AS (
    -- Extract raw vital signs (MAP, HR) within the first 72 hours of ICU stay.
    -- Filter for common itemids for MAP and HR, and typical value ranges.
    SELECT
        ie.stay_id,
        CAST(TIMESTAMP_DIFF(ce.charttime, ie.intime, HOUR) AS INT64) AS hour_offset,
        ce.itemid,
        ce.valuenum
    FROM ICU_RRT_STAYS AS ie
    INNER JOIN `physionet-data.mimiciv_3_1_icu.chartevents` AS ce
        ON ie.stay_id = ce.stay_id
    WHERE
        ce.valuenum IS NOT NULL
        AND (
            (ce.itemid IN (220052, 220181) AND ce.valuenum > 0 AND ce.valuenum < 300) -- MAP in mmHg
            OR (ce.itemid = 220045 AND ce.valuenum > 0 AND ce.valuenum < 300) -- HR in bpm
        )
        -- Limit to first 72 hours of ICU stay, using hour_offset for precision
        AND TIMESTAMP_DIFF(ce.charttime, ie.intime, HOUR) >= 0
        AND TIMESTAMP_DIFF(ce.charttime, ie.intime, HOUR) < 72
),
HOURLY_AGGREGATED_VITALS AS (
    -- Aggregate vital signs for each hour offset
    SELECT
        stay_id,
        hour_offset,
        -- Calculate the minimum MAP for the hour, considering only MAP itemids
        MIN(CASE WHEN itemid IN (220052, 220181) THEN valuenum END) AS min_map_hourly,
        -- Calculate the maximum HR for the hour, considering only HR itemid
        MAX(CASE WHEN itemid = 220045 THEN valuenum END) AS max_hr_hourly
    FROM HOURLY_VITALS_EXTRACTED
    GROUP BY stay_id, hour_offset
),
PATIENT_HOURLY_INSTABILITY AS (
    -- Create a row for every hour (0-71) for each RRT ICU stay and assign instability flags.
    -- If no vital data exists for a specific hour (or no specific vital sign), assume no instability for that hour.
    SELECT
        s.stay_id,
        h.hour_offset,
        -- Determine hypotension for the hour: 1 if min_map_hourly exists and is < 65, else 0
        COALESCE(CASE WHEN hav.min_map_hourly IS NOT NULL AND hav.min_map_hourly < 65 THEN 1 ELSE 0 END, 0) AS final_has_hypotension,
        -- Determine tachycardia for the hour: 1 if max_hr_hourly exists and is > 100, else 0
        COALESCE(CASE WHEN hav.max_hr_hourly IS NOT NULL AND hav.max_hr_hourly > 100 THEN 1 ELSE 0 END, 0) AS final_has_tachycardia,
        -- Calculate hourly instability score: (hypotension_flag + tachycardia_flag) / 2.0
        (COALESCE(CASE WHEN hav.min_map_hourly IS NOT NULL AND hav.min_map_hourly < 65 THEN 1 ELSE 0 END, 0) +
         COALESCE(CASE WHEN hav.max_hr_hourly IS NOT NULL AND hav.max_hr_hourly > 100 THEN 1 ELSE 0 END, 0)) / 2.0 AS hourly_instability_score
    FROM ICU_RRT_STAYS AS s
    CROSS JOIN UNNEST(GENERATE_ARRAY(0, 71)) AS h(hour_offset) -- Generates 72 hours (0 to 71) for each stay
    LEFT JOIN HOURLY_AGGREGATED_VITALS AS hav
        ON s.stay_id = hav.stay_id AND h.hour_offset = hav.hour_offset
),
PATIENT_SUMMARY_METRICS AS (
    -- Aggregate hourly instability into patient-level metrics for the entire 72-hour period.
    SELECT
        stay_id,
        AVG(hourly_instability_score) AS vital_instability_index,
        SUM(final_has_hypotension) AS hypotensive_hours,
        SUM(final_has_tachycardia) AS tachycardic_hours
    FROM PATIENT_HOURLY_INSTABILITY
    GROUP BY stay_id
    -- Ensure there was some potential for vital instability calculation (i.e., not all NULL scores)
    HAVING COUNT(hourly_instability_score) > 0
),
-- NEW CTE: Aggregate all metrics including the quantile array for the target group
TARGET_GROUP_AGGS AS (
    SELECT
        -- Calculate the full quantiles array once
        APPROX_QUANTILES(psm.vital_instability_index, 100) AS vital_instability_quantiles_array,
        -- Calculate other aggregates for the target group
        AVG(psm.hypotensive_hours) AS avg_hypotensive_hours,
        AVG(psm.tachycardic_hours) AS avg_tachycardic_hours,
        AVG(tcd.los) AS avg_icu_los_days,
        AVG(tcd.hospital_expire_flag) AS mortality_rate
    FROM TARGET_COHORT_DATA AS tcd
    INNER JOIN PATIENT_SUMMARY_METRICS AS psm ON tcd.stay_id = psm.stay_id
),
TARGET_GROUP_RESULTS AS (
    SELECT
        'Target Group (Female, 58-68, RRT ICU)' AS cohort_name,
        1 AS order_rank, -- For ordering results
        -- Access elements from the pre-computed quantiles array
        tga.vital_instability_quantiles_array[OFFSET(25)] AS vital_instability_25th_percentile,
        tga.vital_instability_quantiles_array[OFFSET(50)] AS vital_instability_50th_percentile,
        tga.vital_instability_quantiles_array[OFFSET(75)] AS vital_instability_75th_percentile,
        tga.vital_instability_quantiles_array[OFFSET(90)] AS vital_instability_90th_percentile,
        -- Calculate IQR using the accessed elements
        (tga.vital_instability_quantiles_array[OFFSET(75)] - tga.vital_instability_quantiles_array[OFFSET(25)]) AS vital_instability_iqr,
        -- Bring in other aggregated values
        tga.avg_hypotensive_hours,
        tga.avg_tachycardic_hours,
        tga.avg_icu_los_days,
        tga.mortality_rate
    FROM TARGET_GROUP_AGGS AS tga
),
ALL_RRT_GROUP_RESULTS AS (
    SELECT
        'All RRT ICU Patients' AS cohort_name,
        2 AS order_rank, -- For ordering results
        NULL AS vital_instability_25th_percentile, -- Not requested for this group
        NULL AS vital_instability_50th_percentile,
        NULL AS vital_instability_75th_percentile,
        NULL AS vital_instability_90th_percentile,
        NULL AS vital_instability_iqr,
        AVG(psm.hypotensive_hours) AS avg_hypotensive_hours,
        AVG(psm.tachycardic_hours) AS avg_tachycardic_hours,
        AVG(acd.los) AS avg_icu_los_days,
        AVG(acd.hospital_expire_flag) AS mortality_rate
    FROM ALL_RRT_COHORT_DATA AS acd
    INNER JOIN PATIENT_SUMMARY_METRICS AS psm ON acd.stay_id = psm.stay_id
)
-- Combine and display the results for both cohorts
SELECT
    cohort_name,
    vital_instability_25th_percentile,
    vital_instability_50th_percentile,
    vital_instability_75th_percentile,
    vital_instability_90th_percentile,
    vital_instability_iqr,
    avg_hypotensive_hours,
    avg_tachycardic_hours,
    avg_icu_los_days,
    mortality_rate
FROM TARGET_GROUP_RESULTS
UNION ALL
SELECT
    cohort_name,
    vital_instability_25th_percentile,
    vital_instability_50th_percentile,
    vital_instability_75th_percentile,
    vital_instability_90th_percentile,
    vital_instability_iqr,
    avg_hypotensive_hours,
    avg_tachycardic_hours,
    avg_icu_los_days,
    mortality_rate
FROM ALL_RRT_GROUP_RESULTS
ORDER BY order_rank;