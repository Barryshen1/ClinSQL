WITH cohort AS (
    SELECT 
        ie.stay_id,
        ie.subject_id,
        ie.hadm_id,
        ie.los,
        adm.hospital_expire_flag,
        -- Get max temperature in Celsius
        MAX(CASE WHEN ce.itemid = 223762 THEN ce.valuenum 
                 WHEN ce.itemid = 223761 THEN (ce.valuenum - 32) * 5/9 
            END) AS max_temp_c,
        -- Min SpO2
        MIN(CASE WHEN ce.itemid = 220277 THEN ce.valuenum END) AS min_spo2,
        -- Max respiratory rate
        MAX(CASE WHEN ce.itemid = 220210 THEN ce.valuenum END) AS max_rr
    FROM `physionet-data.mimiciv_3_1_icu.icustays` ie
    INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
        ON ie.subject_id = p.subject_id
    INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` adm
        ON ie.hadm_id = adm.hadm_id
    INNER JOIN `physionet-data.mimiciv_3_1_icu.chartevents` ce
        ON ie.stay_id = ce.stay_id
    WHERE p.gender = 'M'
        AND p.anchor_age BETWEEN 63 AND 73
        AND ie.first_careunit IN ('SICU', 'CSICU', 'TSICU')
        AND ce.itemid IN (223761, 223762, 220277, 220210)
        AND ce.valuenum IS NOT NULL
    GROUP BY ie.stay_id, ie.subject_id, ie.hadm_id, ie.los, adm.hospital_expire_flag
    HAVING max_temp_c IS NOT NULL AND min_spo2 IS NOT NULL AND max_rr IS NOT NULL
),

instability_scores AS (
    SELECT *,
        CASE WHEN max_temp_c > 38.5 THEN 1 ELSE 0 END +
        CASE WHEN min_spo2 < 90 THEN 1 ELSE 0 END +
        CASE WHEN max_rr > 20 THEN 1 ELSE 0 END AS instability_score
    FROM cohort
),

quartile_boundary AS (
    SELECT APPROX_QUANTILES(instability_score, 4)[OFFSET(3)] AS q75
    FROM instability_scores
),

top_quartile AS (
    SELECT *,
        instability_score >= (SELECT q75 FROM quartile_boundary) AS is_top_quartile
    FROM instability_scores
),

percentile_top AS (
    SELECT APPROX_QUANTILES(instability_score, 100)[OFFSET(95)] AS p95_score
    FROM top_quartile
    WHERE is_top_quartile
)

SELECT 
    'Top Quartile' AS group_label,
    (SELECT p95_score FROM percentile_top) AS instability_score_95th_percentile,
    AVG(CASE WHEN max_temp_c > 38.5 THEN 1 ELSE 0 END) AS fever_rate,
    AVG(CASE WHEN min_spo2 < 90 THEN 1 ELSE 0 END) AS spo2_low_rate,
    AVG(CASE WHEN max_rr > 20 THEN 1 ELSE 0 END) AS rr_high_rate,
    AVG(los) AS avg_icu_los,
    AVG(hospital_expire_flag) AS mortality_rate
FROM top_quartile
WHERE is_top_quartile

UNION ALL

SELECT 
    'Other' AS group_label,
    NULL AS instability_score_95th_percentile,
    AVG(CASE WHEN max_temp_c > 38.5 THEN 1 ELSE 0 END) AS fever_rate,
    AVG(CASE WHEN min_spo2 < 90 THEN 1 ELSE 0 END) AS spo2_low_rate,
    AVG(CASE WHEN max_rr > 20 THEN 1 ELSE 0 END) AS rr_high_rate,
    AVG(los) AS avg_icu_los,
    AVG(hospital_expire_flag) AS mortality_rate
FROM top_quartile
WHERE NOT is_top_quartile;