WITH eligible_admissions AS (
    SELECT 
        a.hadm_id, 
        a.subject_id, 
        a.admittime, 
        a.dischtime, 
        a.hospital_expire_flag,
        p.anchor_age,
        p.gender
    FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
    INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` p 
        ON a.subject_id = p.subject_id
    WHERE p.gender = 'F'
        AND p.anchor_age BETWEEN 52 AND 62
),
post_ca_admissions AS (
    SELECT 
        e.*
    FROM eligible_admissions e
    INNER JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
        ON e.subject_id = d.subject_id AND e.hadm_id = d.hadm_id
    WHERE d.icd_code = 'I46.9' 
        AND d.icd_version = 10
),
first_icu_stays AS (
    SELECT 
        subject_id, 
        hadm_id, 
        MIN(intime) AS first_icu_intime
    FROM `physionet-data.mimiciv_3_1_icu.icustays`
    GROUP BY subject_id, hadm_id
),
post_ca_with_start AS (
    SELECT 
        p.*,
        COALESCE(i.first_icu_intime, p.admittime) AS start_time
    FROM post_ca_admissions p
    LEFT JOIN first_icu_stays i 
        ON p.subject_id = i.subject_id AND p.hadm_id = i.hadm_id
),
post_ca_instability AS (
    SELECT 
        c.hadm_id,
        c.subject_id,
        c.start_time,
        c.admittime,
        c.dischtime,
        c.hospital_expire_flag,
        COUNT(l.labevent_id) AS instability_score
    FROM post_ca_with_start c
    LEFT JOIN `physionet-data.mimiciv_3_1_hosp.labevents` l
        ON c.subject_id = l.subject_id
        AND l.charttime BETWEEN c.start_time AND TIMESTAMP_ADD(c.start_time, INTERVAL 48 HOUR)
        AND l.flag IN ('ABNORMAL', 'CRITICAL')
    GROUP BY c.hadm_id, c.subject_id, c.start_time, c.admittime, c.dischtime, c.hospital_expire_flag
),
general_admissions AS (
    SELECT 
        e.*
    FROM eligible_admissions e
    LEFT JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
        ON e.subject_id = d.subject_id AND e.hadm_id = d.hadm_id
        AND d.icd_code = 'I46.9' AND d.icd_version = 10
    WHERE d.hadm_id IS NULL  -- exclude cardiac arrest patients
),
general_with_start AS (
    SELECT 
        g.*,
        COALESCE(i.first_icu_intime, g.admittime) AS start_time
    FROM general_admissions g
    LEFT JOIN first_icu_stays i 
        ON g.subject_id = i.subject_id AND g.hadm_id = i.hadm_id
),
general_instability AS (
    SELECT 
        g.hadm_id,
        g.subject_id,
        g.start_time,
        g.admittime,
        g.dischtime,
        g.hospital_expire_flag,
        COUNT(l.labevent_id) AS instability_score
    FROM general_with_start g
    LEFT JOIN `physionet-data.mimiciv_3_1_hosp.labevents` l
        ON g.subject_id = l.subject_id
        AND l.charttime BETWEEN g.start_time AND TIMESTAMP_ADD(g.start_time, INTERVAL 48 HOUR)
        AND l.flag IN ('ABNORMAL', 'CRITICAL')
    GROUP BY g.hadm_id, g.subject_id, g.start_time, g.admittime, g.dischtime, g.hospital_expire_flag
),
post_ca_stats AS (
    SELECT 
        'post-cardiac arrest' AS cohort,
        APPROX_QUANTILES(instability_score, 4)[OFFSET(1)] AS instability_q1,
        APPROX_QUANTILES(instability_score, 2)[OFFSET(1)] AS instability_median,
        APPROX_QUANTILES(TIMESTAMP_DIFF(dischtime, admittime, HOUR), 2)[OFFSET(1)] AS los_median_hours,
        AVG(CAST(hospital_expire_flag AS FLOAT64)) AS mortality_rate
    FROM post_ca_instability
),
general_stats AS (
    SELECT 
        'general inpatient' AS cohort,
        APPROX_QUANTILES(instability_score, 4)[OFFSET(1)] AS instability_q1,
        APPROX_QUANTILES(instability_score, 2)[OFFSET(1)] AS instability_median,
        APPROX_QUANTILES(TIMESTAMP_DIFF(dischtime, admittime, HOUR), 2)[OFFSET(1)] AS los_median_hours,
        AVG(CAST(hospital_expire_flag AS FLOAT64)) AS mortality_rate
    FROM general_instability
)
SELECT * FROM post_ca_stats
UNION ALL
SELECT * FROM general_stats;