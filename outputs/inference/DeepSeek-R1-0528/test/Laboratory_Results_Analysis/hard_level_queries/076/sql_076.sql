WITH cohort AS (
    SELECT 
        adm.subject_id, 
        adm.hadm_id, 
        adm.admittime, 
        adm.dischtime, 
        adm.hospital_expire_flag,
        -- Calculate age at admission
        p.anchor_age + (EXTRACT(YEAR FROM adm.admittime) - p.anchor_year) AS age_at_admission
    FROM `physionet-data.mimiciv_3_1_hosp.admissions` adm
    INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
        ON adm.subject_id = p.subject_id
    WHERE p.gender = 'M'
),
valid_cohort AS (
    SELECT 
        subject_id, 
        hadm_id, 
        admittime, 
        dischtime, 
        hospital_expire_flag,
        DATETIME_DIFF(dischtime, admittime, DAY) AS los_days
    FROM cohort
    WHERE age_at_admission BETWEEN 87 AND 97
),
lab_events AS (
    SELECT 
        vc.hadm_id,
        COUNT(*) AS score  -- Count of critical lab events
    FROM valid_cohort vc
    LEFT JOIN `physionet-data.mimiciv_3_1_hosp.labevents` lab
        ON vc.hadm_id = lab.hadm_id
        AND lab.charttime >= vc.admittime
        AND lab.charttime <= DATETIME_ADD(vc.admittime, INTERVAL 72 HOUR)
        AND lab.flag = 'critically abnormal'  -- Only critical labs
    GROUP BY vc.hadm_id
),
cohort_with_lab AS (
    SELECT 
        vc.*,
        COALESCE(le.score, 0) AS score  -- Include admissions with 0 critical labs
    FROM valid_cohort vc
    LEFT JOIN lab_events le
        ON vc.hadm_id = le.hadm_id
),
p95 AS (
    SELECT 
        APPROX_QUANTILES(score, 100)[OFFSET(95)] AS p95_value
    FROM cohort_with_lab
),
entire_cohort_metrics AS (
    SELECT
        AVG(los_days) AS mean_los,
        AVG(hospital_expire_flag) AS mortality_rate,
        AVG(score) AS avg_critical_lab_events
    FROM cohort_with_lab
),
high_score_metrics AS (
    SELECT
        AVG(los_days) AS mean_los,
        AVG(hospital_expire_flag) AS mortality_rate,
        AVG(score) AS avg_critical_lab_events
    FROM cohort_with_lab
    CROSS JOIN p95
    WHERE score >= p95.p95_value
)
SELECT 
    (SELECT p95_value FROM p95) AS p95_lab_instability_score,
    hsm.mean_los AS high_score_mean_los,
    hsm.mortality_rate AS high_score_mortality_rate,
    hsm.avg_critical_lab_events AS high_score_avg_critical_lab_events,
    ecm.mean_los AS entire_cohort_mean_los,
    ecm.mortality_rate AS entire_cohort_mortality_rate,
    ecm.avg_critical_lab_events AS entire_cohort_avg_critical_lab_events
FROM entire_cohort_metrics ecm, high_score_metrics hsm;