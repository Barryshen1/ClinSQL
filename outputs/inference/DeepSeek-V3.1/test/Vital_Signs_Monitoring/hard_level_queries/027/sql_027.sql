WITH rrt_patients AS (
    SELECT DISTINCT i.subject_id, i.hadm_id, i.stay_id
    FROM `physionet-data.mimiciv_3_1_icu.icustays` i
    INNER JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
        ON i.hadm_id = d.hadm_id
    WHERE d.icd_code IN ('5A1D0Z0', '5A1D0Z1', '5A1D0Z2')  -- ICD10 RRT
        OR d.icd_code IN ('3995')  -- ICD9 Hemodialysis
),
cohort AS (
    SELECT 
        i.subject_id, 
        i.hadm_id, 
        i.stay_id,
        i.intime,
        i.outtime,
        i.los AS icu_los,
        p.anchor_age,
        p.gender,
        a.hospital_expire_flag,
        -- Define target group: female and age between 58 and 68
        CASE WHEN p.gender = 'F' AND p.anchor_age BETWEEN 58 AND 68 THEN 1 ELSE 0 END AS is_target
    FROM `physionet-data.mimiciv_3_1_icu.icustays` i
    INNER JOIN rrt_patients rrt 
        ON i.stay_id = rrt.stay_id
    INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` p 
        ON i.subject_id = p.subject_id
    INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a 
        ON i.hadm_id = a.hadm_id
    -- Get first ICU stay per admission
    WHERE i.stay_id = (
        SELECT MIN(i2.stay_id) 
        FROM `physionet-data.mimiciv_3_1_icu.icustays` i2 
        WHERE i2.hadm_id = i.hadm_id
    )
),
hours AS (
    -- Generate hours for first 72h of ICU stay
    SELECT 
        stay_id,
        hour
    FROM cohort,
        UNNEST(GENERATE_TIMESTAMP_ARRAY(
            TIMESTAMP(intime),
            TIMESTAMP_ADD(TIMESTAMP(intime), INTERVAL 72 HOUR),
            INTERVAL 1 HOUR
        )) AS hour
),
vitals_hourly AS (
    -- Aggregate MAP and HR per hour
    SELECT 
        c.stay_id,
        TIMESTAMP_TRUNC(charttime, HOUR) AS hour,
        AVG(CASE WHEN itemid = 220181 THEN valuenum END) AS map_avg,
        AVG(CASE WHEN itemid = 220045 THEN valuenum END) AS hr_avg
    FROM `physionet-data.mimiciv_3_1_icu.chartevents` c
    INNER JOIN cohort co ON c.stay_id = co.stay_id
    WHERE c.itemid IN (220181, 220045)  -- MAP and HR
        AND c.valuenum IS NOT NULL
        AND c.charttime >= co.intime
        AND c.charttime <= TIMESTAMP_ADD(co.intime, INTERVAL 72 HOUR)
    GROUP BY stay_id, hour
),
flags AS (
    -- For each hour, flag conditions
    SELECT 
        stay_id,
        hour,
        CASE WHEN map_avg < 65 THEN 1 ELSE 0 END AS hypotensive,
        CASE WHEN hr_avg > 100 THEN 1 ELSE 0 END AS tachycardic,
        CASE WHEN map_avg < 65 AND hr_avg > 100 THEN 1 ELSE 0 END AS concurrent
    FROM vitals_hourly
    WHERE map_avg IS NOT NULL AND hr_avg IS NOT NULL  -- must have both
),
patient_metrics AS (
    -- For each patient, compute the proportions
    SELECT 
        f.stay_id,
        AVG(concurrent) AS vital_instability_index,
        AVG(hypotensive) AS hypotensive_hours,
        AVG(tachycardic) AS tachycardic_hours
    FROM flags f
    GROUP BY f.stay_id
),
combined AS (
    SELECT 
        c.*,
        pm.vital_instability_index,
        pm.hypotensive_hours,
        pm.tachycardic_hours
    FROM cohort c
    LEFT JOIN patient_metrics pm ON c.stay_id = pm.stay_id
)
-- Now, for target and other groups, compute percentiles and aggregates
SELECT 
    is_target,
    COUNT(*) AS n_patients,
    -- For vital_instability_index
    APPROX_QUANTILES(vital_instability_index, 100)[OFFSET(25)] AS p25_instability,
    APPROX_QUANTILES(vital_instability_index, 100)[OFFSET(50)] AS p50_instability,
    APPROX_QUANTILES(vital_instability_index, 100)[OFFSET(75)] AS p75_instability,
    APPROX_QUANTILES(vital_instability_index, 100)[OFFSET(90)] AS p90_instability,
    -- Similarly for hypotensive_hours
    APPROX_QUANTILES(hypotensive_hours, 100)[OFFSET(25)] AS p25_hypo,
    APPROX_QUANTILES(hypotensive_hours, 100)[OFFSET(50)] AS p50_hypo,
    APPROX_QUANTILES(hypotensive_hours, 100)[OFFSET(75)] AS p75_hypo,
    APPROX_QUANTILES(hypotensive_hours, 100)[OFFSET(90)] AS p90_hypo,
    -- For tachycardic_hours
    APPROX_QUANTILES(tachycardic_hours, 100)[OFFSET(25)] AS p25_tachy,
    APPROX_QUANTILES(tachycardic_hours, 100)[OFFSET(50)] AS p50_tachy,
    APPROX_QUANTILES(tachycardic_hours, 100)[OFFSET(75)] AS p75_tachy,
    APPROX_QUANTILES(tachycardic_hours, 100)[OFFSET(90)] AS p90_tachy,
    -- Median ICU LOS
    APPROX_QUANTILES(icu_los, 100)[OFFSET(50)] AS median_icu_los,
    -- Mortality rate
    AVG(hospital_expire_flag) AS mortality_rate
FROM combined
GROUP BY is_target
ORDER BY is_target;