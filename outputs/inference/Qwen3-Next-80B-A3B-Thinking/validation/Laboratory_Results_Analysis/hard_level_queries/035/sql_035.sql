WITH cohort AS (
    SELECT DISTINCT a.subject_id, a.hadm_id, a.admittime, a.dischtime, a.hospital_expire_flag
    FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
    JOIN `physionet-data.mimiciv_3_1_hosp.patients` p ON a.subject_id = p.subject_id
    JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d ON a.hadm_id = d.hadm_id
    WHERE p.gender = 'F'
      AND (p.anchor_age + (EXTRACT(YEAR FROM a.admittime) - p.anchor_year)) BETWEEN 78 AND 88
      AND d.icd_version = 10
      AND d.icd_code LIKE 'I63%'
),
lab_counts_cohort AS (
    SELECT 
        c.hadm_id,
        COUNT(l.labevent_id) AS critical_lab_count
    FROM cohort c
    LEFT JOIN `physionet-data.mimiciv_3_1_hosp.labevents` l 
        ON c.hadm_id = l.hadm_id
        AND l.charttime BETWEEN c.admittime AND TIMESTAMP_ADD(c.admittime, INTERVAL 72 HOUR)
        AND l.flag IS NOT NULL
        AND l.flag != 'N'
    GROUP BY c.hadm_id
),
lab_counts_general AS (
    SELECT 
        a.hadm_id,
        COUNT(l.labevent_id) AS critical_lab_count
    FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
    LEFT JOIN `physionet-data.mimiciv_3_1_hosp.labevents` l 
        ON a.hadm_id = l.hadm_id
        AND l.charttime BETWEEN a.admittime AND TIMESTAMP_ADD(a.admittime, INTERVAL 72 HOUR)
        AND l.flag IS NOT NULL
        AND l.flag != 'N'
    GROUP BY a.hadm_id
),
cohort_stats AS (
    SELECT 
        MIN(lc.critical_lab_count) AS min_critical_lab,
        AVG(lc.critical_lab_count) AS avg_cohort_critical_lab,
        AVG(DATETIME_DIFF(c.dischtime, c.admittime, DAY)) AS avg_los,
        AVG(c.hospital_expire_flag) AS mortality_rate
    FROM cohort c
    LEFT JOIN lab_counts_cohort lc ON c.hadm_id = lc.hadm_id
)
SELECT 
    cs.min_critical_lab,
    cs.avg_cohort_critical_lab,
    (SELECT AVG(critical_lab_count) FROM lab_counts_general) AS avg_general_critical_lab,
    cs.avg_los,
    cs.mortality_rate
FROM cohort_stats cs;