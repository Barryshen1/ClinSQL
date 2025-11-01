WITH cohort AS (
    SELECT 
        ie.subject_id, 
        ie.hadm_id, 
        ie.stay_id,
        ie.intime,
        ie.outtime,
        p.anchor_age,
        p.gender
    FROM `physionet-data.mimiciv_3_1_icu.icustays` ie
    INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
        ON ie.subject_id = p.subject_id
    INNER JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` diag
        ON ie.hadm_id = diag.hadm_id
    WHERE p.anchor_age BETWEEN 43 AND 53
        AND p.gender = 'F'
        AND diag.icd_code IN ('J9600', '51881')
),
map_events AS (
    SELECT 
        c.stay_id,
        c.subject_id,
        c.hadm_id,
        ce.charttime,
        ce.valuenum AS map_value
    FROM cohort c
    INNER JOIN `physionet-data.mimiciv_3_1_icu.chartevents` ce
        ON c.stay_id = ce.stay_id
    WHERE ce.itemid = 220181  -- MAP
        AND ce.valuenum IS NOT NULL
        AND ce.charttime BETWEEN c.intime AND DATETIME_ADD(c.intime, INTERVAL 48 HOUR)
),
vii_per_stay AS (
    SELECT 
        stay_id,
        STDDEV(map_value) AS vii
    FROM map_events
    GROUP BY stay_id
),
vii_95th AS (
    SELECT 
        APPROX_QUANTILES(vii, 100)[OFFSET(95)] AS vii_95p
    FROM vii_per_stay
),
vii_75th AS (
    SELECT 
        APPROX_QUANTILES(vii, 100)[OFFSET(75)] AS vii_75p
    FROM vii_per_stay
),
top_quartile_cohort AS (
    SELECT 
        vps.stay_id
    FROM vii_per_stay vps
    CROSS JOIN vii_75th
    WHERE vps.vii >= vii_75p
),
hypotension_episodes AS (
    SELECT 
        stay_id,
        COUNT(DISTINCT charttime) AS hypo_episodes
    FROM map_events
    WHERE map_value < 65
    GROUP BY stay_id
),
hr_events AS (
    SELECT 
        c.stay_id,
        ce.charttime,
        ce.valuenum AS hr_value
    FROM cohort c
    INNER JOIN `physionet-data.mimiciv_3_1_icu.chartevents` ce
        ON c.stay_id = ce.stay_id
    WHERE ce.itemid = 220045  -- Heart rate
        AND ce.valuenum IS NOT NULL
        AND ce.charttime BETWEEN c.intime AND DATETIME_ADD(c.intime, INTERVAL 48 HOUR)
),
tachycardia_episodes AS (
    SELECT 
        stay_id,
        COUNT(DISTINCT charttime) AS tachy_episodes
    FROM hr_events
    WHERE hr_value > 100
    GROUP BY stay_id
),
general_icu AS (
    SELECT 
        ie.stay_id,
        ie.subject_id,
        ie.hadm_id,
        FROM `physionet-data.mimiciv_3_1_icu.icustays` ie
),
mortality AS (
    SELECT 
        hadm_id,
        MAX(hospital_expire_flag) AS mortality
    FROM `physionet-data.mimiciv_3_1_hosp.admissions`
    GROUP BY hadm_id
),
top_quartile_metrics AS (
    SELECT 
        'Top Quartile' AS cohort_type,
        COUNT(DISTINCT tqc.stay_id) AS n_stays,
        AVG(COALESCE(he.hypo_episodes, 0)) AS avg_hypo_episodes,
        AVG(COALESCE(te.tachy_episodes, 0)) AS avg_tachy_episodes,
        AVG(ie.los) AS avg_icu_los,
        AVG(COALESCE(m.mortality, 0)) * 100 AS mortality_percent
    FROM top_quartile_cohort tqc
    INNER JOIN `physionet-data.mimiciv_3_1_icu.icustays` ie
        ON tqc.stay_id = ie.stay_id
    LEFT JOIN hypotension_episodes he
        ON tqc.stay_id = he.stay_id
    LEFT JOIN tachycardia_episodes te
        ON tqc.stay_id = te.stay_id
    LEFT JOIN mortality m
        ON ie.hadm_id = m.hadm_id
),
general_icu_metrics AS (
    SELECT 
        'General ICU' AS cohort_type,
        COUNT(DISTINCT gi.stay_id) AS n_stays,
        AVG(COALESCE(he.hypo_episodes, 0)) AS avg_hypo_episodes,
        AVG(COALESCE(te.tachy_episodes, 0)) AS avg_tachy_episodes,
        AVG(ie.los) AS avg_icu_los,
        AVG(COALESCE(m.mortality, 0)) * 100 AS mortality_percent
    FROM general_icu gi
    INNER JOIN `physionet-data.mimiciv_3_1_icu.icustays` ie
        ON gi.stay_id = ie.stay_id
    LEFT JOIN hypotension_episodes he
        ON gi.stay_id = he.stay_id
    LEFT JOIN tachycardia_episodes te
        ON gi.stay_id = te.stay_id
    LEFT JOIN mortality m
        ON gi.hadm_id = m.hadm_id
)
SELECT 
    vii_95th.vii_95p AS vital_instability_index_95th_percentile,
    tqm.*,
    gim.*
FROM vii_95th,
    top_quartile_metrics tqm,
    general_icu_metrics gim;