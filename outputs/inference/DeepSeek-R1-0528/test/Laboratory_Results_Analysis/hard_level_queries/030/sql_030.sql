WITH all_admissions AS (
    SELECT a.hadm_id, a.admittime
    FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
),
critical_lab_counts AS (
    SELECT
        a.hadm_id,
        COUNT(l.labevent_id) AS critical_count
    FROM all_admissions a
    LEFT JOIN `physionet-data.mimiciv_3_1_hosp.labevents` l
        ON a.hadm_id = l.hadm_id
        AND l.charttime BETWEEN a.admittime AND DATETIME_ADD(a.admittime, INTERVAL 48 HOUR)
        AND l.flag IS NOT NULL
        AND l.flag != 'normal'  -- Exclude normal flags
    GROUP BY a.hadm_id
),
cohort AS (
    SELECT
        a.subject_id,
        a.hadm_id,
        a.admittime,
        a.dischtime,
        a.hospital_expire_flag,
        (EXTRACT(YEAR FROM a.admittime) - (p.anchor_year - p.anchor_age)) AS age_admit
    FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
    INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
        ON a.subject_id = p.subject_id
    WHERE
        p.gender = 'F'
        AND (EXTRACT(YEAR FROM a.admittime) - (p.anchor_year - p.anchor_age)) BETWEEN 39 AND 49
        AND a.hadm_id IN (
            SELECT hadm_id
            FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd`
            WHERE
                (icd_version = 9 AND REGEXP_CONTAINS(icd_code, r'^493\.[0129][12]'))
                OR
                (icd_version = 10 AND REGEXP_CONTAINS(icd_code, r'^J45\.[0-9]+[12]'))
        )
),
cohort_lab AS (
    SELECT
        c.*,
        COALESCE(clc.critical_count, 0) AS critical_count
    FROM cohort c
    LEFT JOIN critical_lab_counts clc
        ON c.hadm_id = clc.hadm_id
)
SELECT
    (SELECT APPROX_QUANTILES(critical_count, 100)[OFFSET(75)]
     FROM cohort_lab) AS cohort_75th_percentile_lab_instability,
    AVG(DATETIME_DIFF(dischtime, admittime, DAY)) AS cohort_avg_los_days,
    AVG(hospital_expire_flag) AS cohort_mortality_rate,
    (SELECT APPROX_QUANTILES(critical_count, 100)[OFFSET(75)]
     FROM critical_lab_counts) AS all_inpatients_75th_percentile_lab_instability
FROM cohort_lab;