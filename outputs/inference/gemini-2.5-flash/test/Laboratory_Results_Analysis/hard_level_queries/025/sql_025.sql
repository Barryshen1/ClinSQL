WITH cohort_base AS (
    SELECT DISTINCT
        a.subject_id,
        a.hadm_id,
        a.admittime,
        a.dischtime,
        a.Hospital_expire_flag,
        p.gender,
        p.anchor_age
    FROM `physionet-data.mimiciv_3_1_hosp.admissions` AS a
    INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` AS p
        ON a.subject_id = p.subject_id
    INNER JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` AS di
        ON a.subject_id = di.subject_id AND a.hadm_id = di.hadm_id
    INNER JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` AS did
        ON di.icd_code = did.icd_code AND di.icd_version = did.icd_version
    WHERE
        p.gender = 'F'
        AND p.anchor_age BETWEEN 48 AND 58
        AND (
            (did.icd_version = 10 AND (did.icd_code LIKE 'I60%' OR did.icd_code LIKE 'I61%' OR did.icd_code LIKE 'I62%'))
            OR (did.icd_version = 9 AND (did.icd_code IN ('430', '431') OR did.icd_code LIKE '432%'))
        )
),
critical_lab_counts AS (
    SELECT
        cb.subject_id,
        cb.hadm_id,
        COUNT(le.labevent_id) AS critical_lab_events_72h
    FROM cohort_base AS cb
    INNER JOIN `physionet-data.mimiciv_3_1_hosp.labevents` AS le
        ON cb.subject_id = le.subject_id AND cb.hadm_id = le.hadm_id
    WHERE
        le.charttime BETWEEN cb.Admittime AND TIMESTAMP_ADD(cb.admittime, INTERVAL 72 HOUR)
        AND le.flag IN ('Abnormal', 'High', 'Low', 'Critical High', 'Critical Low') -- Updated to specifically look for critical flags
        AND le.valuenum IS NOT NULL -- Ensure it's a measurable numeric result
    GROUP BY
        cb.subject_id,
        cb.hadm_id
),
cohort_with_scores_and_percentile AS (
    SELECT
        cb.subject_id,
        cb.hadm_id,
        cb.admittime,
        cb.dischtime,
        cb.hospital_expire_flag,
        cb.anchor_age,
        COALESCE(clc.critical_lab_events_72h, 0) AS lab_instability_score,
        -- Calculate the 90th percentile of lab_instability_score across the entire cohort
        PERCENTILE_CONT(COALESCE(clc.critical_lab_events_72h, 0), 0.9) OVER () AS p90_lab_score_threshold
    FROM cohort_base AS cb
    LEFT JOIN critical_lab_counts AS clc
        ON cb.subject_id = clc.subject_id AND cb.hadm_id = clc.hadm_id
)
-- Final aggregation to get metrics for both groups in a single result row
SELECT
    ANY_VALUE(cws.p90_lab_score_threshold) AS p90_lab_score_threshold,

    -- Metrics for P90+ patients
    SUM(CASE WHEN cws.lab_instability_score >= cws.p90_lab_score_threshold THEN 1 ELSE 0 END) AS num_patients_p90_plus,
    AVG(CASE WHEN cws.lab_instability_score >= cws.p90_lab_score_threshold THEN cws.hospital_expire_flag END) * 100 AS mortality_rate_p90_plus_percent,
    AVG(CASE WHEN cws.lab_instability_score >= cws.p90_lab_score_threshold THEN DATE_DIFF(cws.dischtime, cws.admittime, HOUR) / 24.0 END) AS mean_los_p90_plus_days,
    AVG(CASE WHEN cws.lab_instability_score >= cws.p90_lab_score_threshold THEN cws.lab_instability_score END) AS avg_critical_labs_p90_plus_per_patient,

    -- Metrics for age-matched cohort (all patients in cohort_with_scores_and_percentile)
    COUNT(DISTINCT cws.hadm_id) AS num_patients_age_matched,
    AVG(cws.hospital_expire_flag) * 100 AS mortality_rate_age_matched_percent,
    AVG(DATE_DIFF(cws.dischtime, cws.admittime, HOUR) / 24.0) AS mean_los_age_matched_days,
    AVG(cws.lab_instability_score) AS avg_critical_labs_age_matched_per_patient
FROM cohort_with_scores_and_percentile AS cws;