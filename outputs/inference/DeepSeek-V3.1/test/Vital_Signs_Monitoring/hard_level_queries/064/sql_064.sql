WITH
-- Define ARF patients: male, age 45-55, with ARF diagnosis
arf_patients AS (
    SELECT DISTINCT
        p.subject_id,
        p.gender,
        p.anchor_age,
        i.hadm_id,
        i.stay_id,
        i.intime,
        i.outtime,
        i.los AS icu_los,
        a.hospital_expire_flag
    FROM `physionet-data.mimiciv_3_1_icu.icustays` i
    INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
        ON i.subject_id = p.subject_id
    INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a
        ON i.hadm_id = a.hadm_id
    INNER JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` di
        ON i.hadm_id = di.hadm_id
    INNER JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` dd
        ON di.icd_code = dd.icd_code AND di.icd_version = dd.icd_version
    WHERE p.gender = 'M'
        AND p.anchor_age BETWEEN 45 AND 55
        AND (dd.icd_code LIKE '584%' OR dd.icd_code LIKE 'N17%')
),

-- Get MAP measurements in first 48h
map_events AS (
    SELECT
        ce.stay_id,
        COUNT(*) AS map_count,
        SUM(CASE WHEN ce.valuenum < 65 THEN 1 ELSE 0 END) AS hypotensive_count
    FROM `physionet-data.mimiciv_3_1_icu.chartevents` ce
    INNER JOIN arf_patients ap
        ON ce.stay_id = ap.stay_id
    WHERE ce.itemid IN (220181, 220179)  -- MAP
        AND ce.charttime BETWEEN ap.intime AND DATETIME_ADD(ap.intime, INTERVAL 48 HOUR)
        AND ce.valuenum IS NOT NULL
    GROUP BY ce.stay_id
),

-- Get HR measurements in first 48h
hr_events AS (
    SELECT
        ce.stay_id,
        COUNT(*) AS hr_count,
        SUM(CASE WHEN ce.valuenum > 100 THEN 1 ELSE 0 END) AS tachycardic_count
    FROM `physionet-data.mimiciv_3_1_icu.chartevents` ce
    INNER JOIN arf_patients ap
        ON ce.stay_id = ap.stay_id
    WHERE ce.itemid = 220045  -- Heart Rate
        AND ce.charttime BETWEEN ap.intime AND DATETIME_ADD(ap.intime, INTERVAL 48 HOUR)
        AND ce.valuenum IS NOT NULL
    GROUP BY ce.stay_id
),

-- Compute instability score: sum of hypotensive and tachycardic events
instability_scores AS (
    SELECT
        ap.stay_id,
        COALESCE(me.hypotensive_count, 0) + COALESCE(he.tachycardic_count, 0) AS instability_score
    FROM arf_patients ap
    LEFT JOIN map_events me
        ON ap.stay_id = me.stay_id
    LEFT JOIN hr_events he
        ON ap.stay_id = he.stay_id
),

-- Calculate 95th percentile of instability score
percentile_95 AS (
    SELECT
        APPROX_QUANTILES(instability_score, 100)[OFFSET(95)] AS p95
    FROM instability_scores
),

-- Identify top quartile (top 25%) by instability score
top_quartile AS (
    SELECT
        stay_id,
        instability_score
    FROM instability_scores
    WHERE instability_score >= (
        SELECT APPROX_QUANTILES(instability_score, 4)[OFFSET(3)]
        FROM instability_scores
    )
),

-- Aggregate metrics for top quartile
top_quartile_metrics AS (
    SELECT
        'Top Quartile' AS cohort,
        COUNT(DISTINCT tq.stay_id) AS n,
        -- Proportion with at least one hypotensive event (MAP<65)
        COUNT(DISTINCT CASE WHEN me.hypotensive_count > 0 THEN tq.stay_id END) * 100.0 / COUNT(DISTINCT tq.stay_id) AS hypotension_percent,
        -- Proportion with at least one tachycardic event (HR>100)
        COUNT(DISTINCT CASE WHEN he.tachycardic_count > 0 THEN tq.stay_id END) * 100.0 / COUNT(DISTINCT tq.stay_id) AS tachycardia_percent,
        AVG(ap.icu_los) AS avg_icu_los,
        SUM(ap.hospital_expire_flag) * 100.0 / COUNT(DISTINCT tq.stay_id) AS mortality_percent
    FROM top_quartile tq
    INNER JOIN arf_patients ap
        ON tq.stay_id = ap.stay_id
    LEFT JOIN map_events me
        ON tq.stay_id = me.stay_id
    LEFT JOIN hr_events he
        ON tq.stay_id = he.stay_id
    GROUP BY cohort
),

-- Aggregate metrics for all ARF patients (age-matched cohort)
all_cohort_metrics AS (
    SELECT
        'All ARF Patients' AS cohort,
        COUNT(DISTINCT ap.stay_id) AS n,
        COUNT(DISTINCT CASE WHEN me.hypotensive_count > 0 THEN ap.stay_id END) * 100.0 / COUNT(DISTINCT ap.stay_id) AS hypotension_percent,
        COUNT(DISTINCT CASE WHEN he.tachycardic_count > 0 THEN ap.stay_id END) * 100.0 / COUNT(DISTINCT ap.stay_id) AS tachycardia_percent,
        AVG(ap.icu_los) AS avg_icu_los,
        SUM(ap.hospital_expire_flag) * 100.0 / COUNT(DISTINCT ap.stay_id) AS mortality_percent
    FROM arf_patients ap
    LEFT JOIN map_events me
        ON ap.stay_id = me.stay_id
    LEFT JOIN hr_events he
        ON ap.stay_id = he.stay_id
    GROUP BY cohort
)

-- Output the 95th percentile and the comparison
SELECT
    (SELECT p95 FROM percentile_95) AS instability_score_95th_percentile,
    tq.*,
    ac.*
FROM top_quartile_metrics tq
CROSS JOIN all_cohort_metrics ac;