WITH cohort AS (
    SELECT 
        p.subject_id, 
        p.gender, 
        p.anchor_age,
        a.hadm_id, 
        a.admittime, 
        a.dischtime, 
        a.hospital_expire_flag,
        DATETIME_DIFF(a.dischtime, a.admittime, DAY) AS los_days
    FROM `physionet-data.mimiciv_3_1_hosp.patients` p
    INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a
        ON p.subject_id = a.subject_id
    INNER JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` diag
        ON a.hadm_id = diag.hadm_id
    INNER JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` d
        ON diag.icd_code = d.icd_code AND diag.icd_version = d.icd_version
    WHERE p.gender = 'F'
        AND p.anchor_age BETWEEN 53 AND 63
        AND d.long_title LIKE 'Cardiac arrest%'
),

labs_48hr AS (
    SELECT 
        c.subject_id,
        c.hadm_id,
        COUNT(DISTINCT l.itemid) AS instability_score
    FROM cohort c
    LEFT JOIN `physionet-data.mimiciv_3_1_hosp.labevents` l
        ON c.hadm_id = l.hadm_id
        AND l.charttime BETWEEN c.admittime AND DATETIME_ADD(c.admittime, INTERVAL 48 HOUR)
        AND l.flag IS NOT NULL
    GROUP BY c.subject_id, c.hadm_id
),

percentile_calc AS (
    SELECT 
        PERCENTILE_CONT(instability_score, 0.9) OVER() AS p90_score
    FROM labs_48hr
    LIMIT 1
),

high_instability_cohort AS (
    SELECT 
        c.*,
        l.instability_score
    FROM cohort c
    INNER JOIN labs_48hr l
        ON c.hadm_id = l.hadm_id
    CROSS JOIN percentile_calc p
    WHERE l.instability_score >= p.p90_score
),

all_inpatients_labs AS (
    SELECT 
        a.hadm_id,
        COUNT(DISTINCT l.itemid) AS abnormal_labs_count
    FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
    LEFT JOIN `physionet-data.mimiciv_3_1_hosp.labevents` l
        ON a.hadm_id = l.hadm_id
        AND l.flag IS NOT NULL
    GROUP BY a.hadm_id
)

SELECT 
    (SELECT COUNT(*) FROM high_instability_cohort) AS n_patients,
    (SELECT COUNT(*) FROM high_instability_cohort WHERE hospital_expire_flag = 1) AS n_died,
    (SELECT AVG(los_days) FROM high_instability_cohort) AS mean_los_days,
    (SELECT AVG(instability_score) FROM high_instability_cohort) AS mean_abnormal_labs_subgroup,
    (SELECT AVG(abnormal_labs_count) FROM all_inpatients_labs) AS mean_abnormal_labs_all_inpatients;