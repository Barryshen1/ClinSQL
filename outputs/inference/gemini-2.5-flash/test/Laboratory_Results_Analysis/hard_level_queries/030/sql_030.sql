WITH cohort_admissions AS (
    SELECT DISTINCT
        p.subject_id,
        a.hadm_id,
        a.admittime,
        a.dischtime,
        a.hospital_expire_flag,
        DATETIME_DIFF(a.dischtime, a.admittime, HOUR) / 24.0 AS los_days
    FROM
        `physionet-data.mimiciv_3_1_hosp.patients` p
    INNER JOIN
        `physionet-data.mimiciv_3_1_hosp.admissions` a
        ON p.subject_id = a.subject_id
    INNER JOIN
        `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` di
        ON a.subject_id = di.subject_id AND a.hadm_id = di.hadm_id
    WHERE
        p.gender = 'F'
        AND (p.anchor_age + (EXTRACT(YEAR FROM a.admittime) - p.anchor_year)) BETWEEN 39 AND 49
        AND (
            (di.icd_version = 9 AND di.icd_code IN ('49301', '49311', '49321', '49391'))
            OR
            (di.icd_version = 10 AND di.icd_code IN ('J4521', 'J4531', 'J4541', 'J4551', 'J45901', 'J45902'))
        )
),
-- Calculate critical lab events per admission for the cohort, including those with 0 events
cohort_critical_lab_events_per_adm AS (
    SELECT
        ca.hadm_id,
        COUNT(DISTINCT le.labevent_id) AS critical_lab_events_count
    FROM
        cohort_admissions ca
    LEFT JOIN
        `physionet-data.mimiciv_3_1_hosp.labevents` le
        ON ca.subject_id = le.subject_id
        AND ca.hadm_id = le.hadm_id
        AND le.charttime BETWEEN ca.admittime AND DATETIME_ADD(ca.admittime, INTERVAL 48 HOUR)
        AND le.flag = 'abnormal'
    GROUP BY
        ca.hadm_id
),
-- Calculate critical lab events per admission for all inpatients, including those with 0 events
all_inpatients_critical_lab_events_per_adm AS (
    SELECT
        a.hadm_id,
        COUNT(DISTINCT le.labevent_id) AS critical_lab_events_count
    FROM
        `physionet-data.mimiciv_3_1_hosp.admissions` a
    LEFT JOIN
        `physionet-data.mimiciv_3_1_hosp.labevents` le
        ON a.subject_id = le.subject_id
        AND a.hadm_id = le.hadm_id
        AND le.charttime BETWEEN a.admittime AND DATETIME_ADD(a.admittime, INTERVAL 48 HOUR)
        AND le.flag = 'abnormal'
    GROUP BY
        a.hadm_id
)
-- Metric 1: Cohort 75th Percentile Lab Instability Score (first 48 hours)
SELECT
    'Cohort 75th Percentile Lab Instability Score (first 48 hours)' AS metric_description,
    (SELECT APPROX_QUANTILES(critical_lab_events_count, 100)[OFFSET(75)] FROM cohort_critical_lab_events_per_adm) AS value

UNION ALL

-- Metric 2: Cohort Average Critical Lab Events per Admission (first 48 hours)
SELECT
    'Cohort Average Critical Lab Events per Admission (first 48 hours)' AS metric_description,
    AVG(ccle.critical_lab_events_count) AS value
FROM
    cohort_critical_lab_events_per_adm ccle

UNION ALL

-- Metric 3: All Inpatients Average Critical Lab Events per Admission (first 48 hours)
SELECT
    'All Inpatients Average Critical Lab Events per Admission (first 48 hours)' AS metric_description,
    AVG(aicle.critical_lab_events_count) AS value
FROM
    all_inpatients_critical_lab_events_per_adm aicle

UNION ALL

-- Metric 4: Cohort Average Length of Stay (Days)
SELECT
    'Cohort Average Length of Stay (Days)' AS metric_description,
    AVG(ca.los_days) AS value
FROM
    cohort_admissions ca

UNION ALL

-- Metric 5: Cohort In-hospital Mortality Rate
SELECT
    'Cohort In-hospital Mortality Rate' AS metric_description,
    SAFE_DIVIDE(SUM(ca.hospital_expire_flag), COUNT(ca.hadm_id)) AS value
FROM
    cohort_admissions ca;