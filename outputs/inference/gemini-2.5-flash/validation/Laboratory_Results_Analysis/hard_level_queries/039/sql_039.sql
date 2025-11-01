WITH cohort_admissions AS (
    SELECT
        adm.subject_id,
        adm.hadm_id,
        adm.admittime,
        adm.dischtime,
        adm.hospital_expire_flag,
        DATETIME_DIFF(adm.dischtime, adm.admittime, HOUR) / 24.0 AS los_days,
        p.gender,
        (p.anchor_age + (EXTRACT(YEAR FROM adm.admittime) - p.anchor_year)) AS age_at_admission
    FROM
        `physionet-data.mimiciv_3_1_hosp.admissions` adm
    INNER JOIN
        `physionet-data.mimiciv_3_1_hosp.patients` p
        ON adm.subject_id = p.subject_id
    INNER JOIN
        `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` dicd
        ON adm.subject_id = dicd.subject_id AND adm.hadm_id = dicd.hadm_id
    WHERE
        p.gender = 'M'
        AND (p.anchor_age + (EXTRACT(YEAR FROM adm.admittime) - p.anchor_year)) BETWEEN 60 AND 70
        AND dicd.seq_num = 1 -- Primary diagnosis
        AND (
            (dicd.icd_version = 9 AND dicd.icd_code BETWEEN '480' AND '486') -- ICD-9 codes for pneumonia
            OR (dicd.icd_version = 10 AND dicd.icd_code BETWEEN 'J12' AND 'J18') -- ICD-10 codes for pneumonia
        )
),
-- Step 2: Calculate abnormal lab events within the first 72 hours for the cohort
cohort_abnormal_labs_72h AS (
    SELECT
        ca.subject_id,
        ca.hadm_id,
        COUNT(le.labevent_id) AS abnormal_lab_count_72h
    FROM
        cohort_admissions ca
    INNER JOIN
        `physionet-data.mimiciv_3_1_hosp.labevents` le
        ON ca.subject_id = le.subject_id AND ca.hadm_id = le.hadm_id
    WHERE
        le.charttime BETWEEN ca.admittime AND DATETIME_ADD(ca.admittime, INTERVAL 72 HOUR)
        AND le.flag = 'abnormal'
    GROUP BY
        ca.subject_id, ca.hadm_id
),
-- Step 3: Calculate total abnormal lab events for the entire stay for the cohort
cohort_abnormal_labs_total_stay AS (
    SELECT
        ca.subject_id,
        ca.hadm_id,
        COUNT(le.labevent_id) AS abnormal_lab_count_total_stay
    FROM
        cohort_admissions ca
    INNER JOIN
        `physionet-data.mimiciv_3_1_hosp.labevents` le
        ON ca.subject_id = le.subject_id AND ca.hadm_id = le.hadm_id
    WHERE
        le.flag = 'abnormal'
    GROUP BY
        ca.subject_id, ca.hadm_id
),
-- Step 4: Combine cohort data with calculated lab metrics
cohort_with_metrics AS (
    SELECT
        ca.subject_id,
        ca.hadm_id,
        ca.los_days,
        ca.hospital_expire_flag,
        COALESCE(c72h.abnormal_lab_count_72h, 0) AS lab_instability_score_72h,
        CASE
            WHEN ca.los_days > 0 THEN COALESCE(ctot.abnormal_lab_count_total_stay, 0) / ca.los_days
            ELSE 0
        END AS cohort_critical_event_frequency_per_day
    FROM
        cohort_admissions ca
    LEFT JOIN
        cohort_abnormal_labs_72h c72h
        ON ca.subject_id = c72h.subject_id AND ca.hadm_id = c72h.hadm_id
    LEFT JOIN
        cohort_abnormal_labs_total_stay ctot
        ON ca.subject_id = ctot.subject_id AND ca.hadm_id = ctot.hadm_id
),
-- Step 5: Calculate total abnormal lab events for ALL admissions (for comparison)
all_admissions_abnormal_labs_total_stay AS (
    SELECT
        adm.subject_id,
        adm.hadm_id,
        DATETIME_DIFF(adm.dischtime, adm.admittime, HOUR) / 24.0 AS los_days,
        COUNT(le.labevent_id) AS abnormal_lab_count_total_stay
    FROM
        `physionet-data.mimiciv_3_1_hosp.admissions` adm
    INNER JOIN
        `physionet-data.mimiciv_3_1_hosp.labevents` le
        ON adm.subject_id = le.subject_id AND adm.hadm_id = le.hadm_id
    WHERE
        le.flag = 'abnormal'
    GROUP BY
        adm.subject_id, adm.hadm_id, los_days
),
-- Step 6: Calculate critical event frequency for all admissions
all_admissions_critical_event_frequency AS (
    SELECT
        subject_id,
        hadm_id,
        CASE
            WHEN los_days > 0 THEN abnormal_lab_count_total_stay / los_days
            ELSE 0
        END AS critical_event_frequency_per_day
    FROM
        all_admissions_abnormal_labs_total_stay
)
-- Final aggregation and results
SELECT
    -- Cohort Metrics
    'Main Cohort (Primary Pneumonia, Male, Age 60-70)' AS cohort_description,
    APPROX_QUANTILES(cwm.lab_instability_score_72h, 100)[OFFSET(75)] AS cohort_75th_percentile_lab_instability_score_72h,
    AVG(cwm.cohort_critical_event_frequency_per_day) AS cohort_mean_critical_event_frequency_per_day,
    AVG(cwm.los_days) AS cohort_mean_los_days,
    SUM(cwm.hospital_expire_flag) * 100.0 / COUNT(cwm.hadm_id) AS cohort_mortality_percentage,
    -- All Inpatients Comparison Metric
    'All Inpatients (for Critical Event Frequency comparison)' AS comparison_group_description,
    (SELECT AVG(aacef.critical_event_frequency_per_day) FROM all_admissions_critical_event_frequency aacef) AS all_inpatients_mean_critical_event_frequency_per_day
FROM
    cohort_with_metrics cwm;