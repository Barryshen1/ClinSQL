WITH sepsis_cohort AS (
    SELECT DISTINCT
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
    INNER JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
        ON a.hadm_id = d.hadm_id
    WHERE 
        p.gender = 'F'
        AND p.anchor_age BETWEEN 43 AND 53
        AND (
            (d.icd_version = 9 AND d.icd_code LIKE '038%') OR
            (d.icd_version = 9 AND d.icd_code IN ('99591', '99592')) OR
            (d.icd_version = 10 AND d.icd_code LIKE 'A41%') OR
            (d.icd_version = 10 AND d.icd_code LIKE 'R65.2%')
        )
),

critical_labs AS (
    SELECT 
        sc.hadm_id,
        COUNT(DISTINCT le.labevent_id) AS critical_lab_count
    FROM sepsis_cohort sc
    LEFT JOIN `physionet-data.mimiciv_3_1_hosp.labevents` le
        ON sc.hadm_id = le.hadm_id
        AND le.charttime BETWEEN sc.admittime AND DATETIME_ADD(sc.admittime, INTERVAL 72 HOUR)
        AND le.flag IS NOT NULL  -- indicates abnormal (critical) lab
    GROUP BY sc.hadm_id
)

SELECT
    COUNT(DISTINCT sc.hadm_id) AS cohort_size,
    AVG(cl.critical_lab_count) AS mean_critical_events,
    APPROX_QUANTILES(cl.critical_lab_count, 100)[OFFSET(25)] AS percentile_25,
    AVG(sc.los_days) AS mean_los_days,
    SUM(sc.hospital_expire_flag) AS mortality_count,
    ROUND(SUM(sc.hospital_expire_flag) / COUNT(DISTINCT sc.hadm_id) * 100, 2) AS mortality_percent
FROM sepsis_cohort sc
INNER JOIN critical_labs cl
    ON sc.hadm_id = cl.hadm_id;