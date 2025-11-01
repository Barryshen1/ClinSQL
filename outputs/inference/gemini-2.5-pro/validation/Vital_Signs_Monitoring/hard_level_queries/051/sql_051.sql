WITH
-- CTE 1: Define the base cohort of male ICU patients aged 89-99
icu_base AS (
    SELECT
        icu.subject_id,
        icu.hadm_id,
        icu.stay_id,
        icu.intime,
        icu.outtime,
        adm.hospital_expire_flag,
        (EXTRACT(YEAR FROM icu.intime) - p.anchor_year) + p.anchor_age AS age_at_intime
    FROM `physionet-data.mimiciv_3_1_icu.icustays` AS icu
    INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` AS p
        ON icu.subject_id = p.subject_id
    INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` AS adm
        ON icu.hadm_id = adm.hadm_id
    WHERE
        p.gender = 'M'
        AND (EXTRACT(YEAR FROM icu.intime) - p.anchor_year) + p.anchor_age BETWEEN 89 AND 99
),

-- CTE 2: Identify hospital admissions with an ischemic stroke diagnosis
stroke_stays AS (
    SELECT DISTINCT hadm_id
    FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd`
    WHERE
        (icd_version = 9 AND (icd_code LIKE '433%1' OR icd_code LIKE '434%1'))
        OR (icd_version = 10 AND icd_code LIKE 'I63%')
),

-- CTE 3: Collect all abnormal measurements (vitals and labs) in the first 48 hours
abnormal_events AS (
    -- Abnormal Vitals from chartevents
    SELECT
        ib.stay_id,
        ce.itemid
    FROM icu_base AS ib
    INNER JOIN `physionet-data.mimiciv_3_1_icu.chartevents` AS ce
        ON ib.stay_id = ce.stay_id
    INNER JOIN `physionet-data.mimiciv_3_1_icu.d_items` AS di
        ON ce.itemid = di.itemid
    WHERE
        ce.charttime BETWEEN ib.intime AND DATETIME_ADD(ib.intime, INTERVAL 48 HOUR)
        AND ce.itemid IN (
            220045, -- Heart Rate
            220052, -- Arterial Blood Pressure mean
            220210, -- Respiratory Rate
            220277, -- O2 saturation pulseoxymetry
            223762  -- Temperature Celsius
        )
        AND ce.valuenum IS NOT NULL
        AND di.lownormalvalue IS NOT NULL AND di.highnormalvalue IS NOT NULL
        AND (ce.valuenum < di.lownormalvalue OR ce.valuenum > di.highnormalvalue)

    UNION ALL

    -- Abnormal Labs from labevents
    SELECT
        ib.stay_id,
        le.itemid
    FROM icu_base AS ib
    INNER JOIN `physionet-data.mimiciv_3_1_hosp.labevents` AS le
        ON ib.hadm_id = le.hadm_id
    WHERE
        le.charttime BETWEEN ib.intime AND DATETIME_ADD(ib.intime, INTERVAL 48 HOUR)
        AND le.itemid IN (
            50813, -- Lactate
            50912, -- Creatinine
            50971, -- Potassium
            50820  -- pH
        )
        AND le.valuenum IS NOT NULL
        AND le.ref_range_lower IS NOT NULL AND le.ref_range_upper IS NOT NULL
        AND (le.valuenum < le.ref_range_lower OR le.valuenum > le.ref_range_upper)
),

-- CTE 4: Calculate instability scores for each ICU stay based on abnormal events
instability_scores AS (
    SELECT
        stay_id,
        COUNT(*) AS instability_score,
        COUNT(DISTINCT itemid) AS abnormal_episodes
    FROM abnormal_events
    GROUP BY stay_id
),

-- CTE 5: Combine base cohort data with instability scores and stroke diagnosis
final_cohort AS (
    SELECT
        ib.stay_id,
        ib.hadm_id,
        ib.intime,
        ib.outtime,
        ib.hospital_expire_flag,
        COALESCE(isc.instability_score, 0) AS instability_score,
        COALESCE(isc.abnormal_episodes, 0) AS abnormal_episodes,
        CASE
            WHEN ss.hadm_id IS NOT NULL THEN 1
            ELSE 0
        END AS is_stroke
    FROM icu_base AS ib
    LEFT JOIN instability_scores AS isc
        ON ib.stay_id = isc.stay_id
    LEFT JOIN stroke_stays AS ss
        ON ib.hadm_id = ss.hadm_id
),

-- CTE 6: Calculate the required percentiles to answer the questions
percentiles AS (
    SELECT
        -- 95th percentile instability score for the ischemic stroke group
        PERCENTILE_CONT(IF(is_stroke = 1, instability_score, NULL), 0.95) OVER() AS p95_stroke_instability,
        -- 75th percentile instability score for the general ICU group (to define top quartile)
        PERCENTILE_CONT(instability_score, 0.75) OVER() AS p75_general_instability
    FROM final_cohort
    LIMIT 1
),

-- CTE 7: Filter for the top instability quartile of the general ICU population
top_quartile_cohort AS (
    SELECT
        fc.*
    FROM final_cohort AS fc
    CROSS JOIN percentiles AS p
    WHERE fc.instability_score >= p.p75_general_instability
)

-- Final Step: Generate the two requested report parts and union them for a single output.

-- Part 1: The 95th-percentile score for ischemic stroke
SELECT
    '95th-percentile 48-hour instability score' AS metric,
    'Ischemic Stroke' AS cohort,
    CAST(p.p95_stroke_instability AS STRING) AS n_or_value,
    NULL AS mean_instability,
    NULL AS mean_abnormal_episodes,
    NULL AS mean_icu_los_hrs,
    NULL AS mortality_rate
FROM percentiles p

UNION ALL

-- Separator for clarity in the final output
SELECT
    '--- Top Instability Quartile Comparison ---' AS metric,
    NULL, NULL, NULL, NULL, NULL, NULL

UNION ALL

-- Part 2: Comparison for the top instability quartile - Ischemic Stroke
SELECT
    'Comparison' AS metric,
    'Ischemic Stroke' AS cohort,
    CAST(COUNT(stay_id) AS STRING) AS n_or_value,
    AVG(instability_score) AS mean_instability,
    AVG(abnormal_episodes) AS mean_abnormal_episodes,
    AVG(DATETIME_DIFF(outtime, intime, HOUR)) AS mean_icu_los_hrs,
    AVG(hospital_expire_flag) * 100 AS mortality_rate
FROM top_quartile_cohort
WHERE is_stroke = 1

UNION ALL

-- Part 2: Comparison for the top instability quartile - General ICU
SELECT
    'Comparison' AS metric,
    'General ICU' AS cohort,
    CAST(COUNT(stay_id) AS STRING) AS n_or_value,
    AVG(instability_score) AS mean_instability,
    AVG(abnormal_episodes) AS mean_abnormal_episodes,
    AVG(DATETIME_DIFF(outtime, intime, HOUR)) AS mean_icu_los_hrs,
    AVG(hospital_expire_flag) * 100 AS mortality_rate
FROM top_quartile_cohort;