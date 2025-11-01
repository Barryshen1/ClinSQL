WITH rrt_patients AS (
    SELECT DISTINCT stay_id
    FROM `physionet-data.mimiciv_3_1_icu.procedureevents`
    WHERE itemid IN (
        SELECT itemid 
        FROM `physionet-data.mimiciv_3_1_icu.d_items` 
        WHERE LOWER(label) LIKE '%dialysis%' 
          OR LOWER(label) LIKE '%crrt%' 
          OR LOWER(label) LIKE '%renal replacement%'
    )
),
base AS (
    SELECT 
        p.subject_id, 
        p.anchor_age,
        p.gender,
        i.hadm_id,
        i.stay_id,
        i.intime,
        i.outtime,
        i.los,
        a.hospital_expire_flag AS mortality,
        CASE 
            WHEN p.gender = 'F' AND p.anchor_age BETWEEN 58 AND 68 THEN 1 
            ELSE 0 
        END AS cohort_flag
    FROM `physionet-data.mimiciv_3_1_hosp.patients` p
    INNER JOIN `physionet-data.mimiciv_3_1_icu.icustays` i
        ON p.subject_id = i.subject_id
    INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a
        ON i.hadm_id = a.hadm_id
    INNER JOIN rrt_patients r
        ON i.stay_id = r.stay_id
),
bins AS (
    SELECT 
        base.*,
        hour_offset,
        DATETIME_ADD(base.intime, INTERVAL hour_offset HOUR) AS bin_start,
        DATETIME_ADD(base.intime, INTERVAL hour_offset + 1 HOUR) AS bin_end
    FROM base
    CROSS JOIN UNNEST(GENERATE_ARRAY(0, 71)) AS hour_offset
    WHERE DATETIME_ADD(base.intime, INTERVAL hour_offset HOUR) < base.outtime
),
map_data AS (
    SELECT 
        bins.stay_id,
        bins.hour_offset,
        MAX(CASE WHEN ce.valuenum < 65 THEN 1 ELSE 0 END) AS map_low,
        MAX(1) AS has_map
    FROM bins
    LEFT JOIN `physionet-data.mimiciv_3_1_icu.chartevents` ce
        ON bins.stay_id = ce.stay_id
        AND ce.charttime >= bins.bin_start
        AND ce.charttime < LEAST(bins.bin_end, bins.outtime)
        AND ce.itemid IN (456, 52, 6702, 220052, 220181, 225312)
    GROUP BY bins.stay_id, bins.hour_offset
),
hr_data AS (
    SELECT 
        bins.stay_id,
        bins.hour_offset,
        MAX(CASE WHEN ce.valuenum > 100 THEN 1 ELSE 0 END) AS hr_high,
        MAX(1) AS has_hr
    FROM bins
    LEFT JOIN `physionet-data.mimiciv_3_1_icu.chartevents` ce
        ON bins.stay_id = ce.stay_id
        AND ce.charttime >= bins.bin_start
        AND ce.charttime < LEAST(bins.bin_end, bins.outtime)
        AND ce.itemid IN (211, 220045)
    GROUP BY bins.stay_id, bins.hour_offset
),
bin_flags AS (
    SELECT 
        bins.stay_id,
        bins.cohort_flag,
        bins.hour_offset,
        COALESCE(map_data.map_low, 0) AS map_low,
        COALESCE(map_data.has_map, 0) AS has_map,
        COALESCE(hr_data.hr_high, 0) AS hr_high,
        COALESCE(hr_data.has_hr, 0) AS has_hr
    FROM bins
    LEFT JOIN map_data
        ON bins.stay_id = map_data.stay_id 
        AND bins.hour_offset = map_data.hour_offset
    LEFT JOIN hr_data
        ON bins.stay_id = hr_data.stay_id 
        AND bins.hour_offset = hr_data.hour_offset
),
patient_bins_agg AS (
    SELECT 
        stay_id,
        cohort_flag,
        COUNT(*) AS total_bins,
        COUNTIF(has_map = 1 AND has_hr = 1) AS assessable_bins,
        COUNTIF(has_map = 1 AND has_hr = 1 AND map_low = 1 AND hr_high = 1) AS unstable_bins,
        COUNTIF(map_low = 1) AS hypotensive_bins,
        COUNTIF(hr_high = 1) AS tachycardic_bins
    FROM bin_flags
    GROUP BY stay_id, cohort_flag
),
patient_metrics AS (
    SELECT 
        base.*,
        CASE 
            WHEN base.cohort_flag = 1 AND COALESCE(pb.assessable_bins, 0) > 0 
            THEN pb.unstable_bins / pb.assessable_bins 
            ELSE NULL 
        END AS vital_instability_index,
        COALESCE(pb.hypotensive_bins, 0) AS hypotensive_hours,
        COALESCE(pb.tachycardic_bins, 0) AS tachycardic_hours
    FROM base
    LEFT JOIN patient_bins_agg pb
        ON base.stay_id = pb.stay_id
)

-- Section 1: Vital-instability index percentiles for target cohort
SELECT 
    -1 AS cohort_flag,
    (SELECT COUNT(*) 
     FROM patient_metrics 
     WHERE cohort_flag = 1 
       AND vital_instability_index IS NOT NULL) AS n_patients,
    approx_quantities[ORDINAL(25)] AS vital_instability_index_p25,
    approx_quantities[ORDINAL(50)] AS vital_instability_index_p50,
    approx_quantities[ORDINAL(75)] AS vital_instability_index_p75,
    approx_quantities[ORDINAL(90)] AS vital_instability_index_p90,
    NULL AS hypotensive_hours_p25,
    NULL AS hypotensive_hours_p50,
    NULL AS hypotensive_hours_p75,
    NULL AS hypotensive_hours_p90,
    NULL AS tachycardic_hours_p25,
    NULL AS tachycardic_hours_p50,
    NULL AS tachycardic_hours_p75,
    NULL AS tachycardic_hours_p90,
    NULL AS los_p25,
    NULL AS los_p50,
    NULL AS los_p75,
    NULL AS los_p90,
    NULL AS mortality_count,
    NULL AS mortality_rate
FROM (
    SELECT APPROX_QUANTILES(vital_instability_index, 100) AS approx_quantities
    FROM patient_metrics
    WHERE cohort_flag = 1 
      AND vital_instability_index IS NOT NULL
)

UNION ALL

-- Section 2: Comparison metrics (target cohort vs. other RRT patients)
SELECT 
    cohort_flag,
    COUNT(*) AS n_patients,
    NULL, NULL, NULL, NULL,
    APPROX_QUANTILES(hypotensive_hours, 100)[ORDINAL(25)] AS hypotensive_hours_p25,
    APPROX_QUANTILES(hypotensive_hours, 100)[ORDINAL(50)] AS hypotensive_hours_p50,
    APPROX_QUANTILES(hypotensive_hours, 100)[ORDINAL(75)] AS hypotensive_hours_p75,
    APPROX_QUANTILES(hypotensive_hours, 100)[ORDINAL(90)] AS hypotensive_hours_p90,
    APPROX_QUANTILES(tachycardic_hours, 100)[ORDINAL(25)] AS tachycardic_hours_p25,
    APPROX_QUANTILES(tachycardic_hours, 100)[ORDINAL(50)] AS tachycardic_hours_p50,
    APPROX_QUANTILES(tachycardic_hours, 100)[ORDINAL(75)] AS tachycardic_hours_p75,
    APPROX_QUANTILES(tachycardic_hours, 100)[ORDINAL(90)] AS tachycardic_hours_p90,
    APPROX_QUANTILES(los, 100)[ORDINAL(25)] AS los_p25,
    APPROX_QUANTILES(los, 100)[ORDINAL(50)] AS los_p50,
    APPROX_QUANTILES(los, 100)[ORDINAL(75)] AS los_p75,
    APPROX_QUANTILES(los, 100)[ORDINAL(90)] AS los_p90,
    SUM(mortality) AS mortality_count,
    AVG(mortality) AS mortality_rate
FROM patient_metrics
GROUP BY cohort_flag;