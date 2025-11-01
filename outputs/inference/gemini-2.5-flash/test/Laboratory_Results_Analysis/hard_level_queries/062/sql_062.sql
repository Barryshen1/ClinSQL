WITH sepsis_admissions AS (
    -- Step 1: Identify the cohort of female patients aged 43-53 with a sepsis diagnosis
    SELECT
        ad.subject_id,
        ad.hadm_id,
        ad.admittime,
        ad.dischtime,
        ad.hospital_expire_flag
    FROM
        `physionet-data.mimiciv_3_1_hosp.admissions` AS ad
    INNER JOIN
        `physionet-data.mimiciv_3_1_hosp.patients` AS p
        ON ad.subject_id = p.subject_id
    INNER JOIN
        `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` AS di
        ON ad.subject_id = di.subject_id AND ad.hadm_id = di.hadm_id
    WHERE
        p.gender = 'F'
        AND p.anchor_age BETWEEN 43 AND 53
        AND (
            -- ICD-10 codes for Sepsis, Severe Sepsis, Septic Shock
            (di.icd_version = 10 AND (di.icd_code LIKE 'A40%' OR di.icd_code LIKE 'A41%' OR di.icd_code LIKE 'R652%'))
            OR
            -- ICD-9 codes for Septicemia, Sepsis, Severe Sepsis, Septic Shock
            (di.icd_version = 9 AND (di.icd_code LIKE '038%' OR di.icd_code IN ('78552', '99591', '99592')))
        )
    GROUP BY
        ad.subject_id, ad.hadm_id, ad.admittime, ad.dischtime, ad.hospital_expire_flag
),
critical_lab_events AS (
    -- Step 2: Count critical lab events within the first 72 hours for each admission in the cohort
    SELECT
        sa.subject_id,
        sa.hadm_id,
        sa.admittime,
        sa.dischtime,
        sa.hospital_expire_flag,
        -- Count lab events flagged as critically low ('LL') or critically high ('HH')
        -- occurring within the first 72 hours of admission.
        -- Use COUNT(CASE ...) with LEFT JOIN to include admissions with 0 critical events.
        COUNT(CASE
            WHEN le.charttime BETWEEN sa.admittime AND DATETIME_ADD(sa.admittime, INTERVAL 72 HOUR)
            AND (le.flag = 'LL' OR le.flag = 'HH')
            THEN le.labevent_id
        END) AS critical_events_72hr
    FROM
        sepsis_admissions AS sa
    LEFT JOIN -- Use LEFT JOIN to ensure all sepsis admissions are included, even if they have no relevant lab events
        `physionet-data.mimiciv_3_1_hosp.labevents` AS le
        ON sa.subject_id = le.subject_id AND sa.hadm_id = le.hadm_id
    GROUP BY
        sa.subject_id, sa.hadm_id, sa.admittime, sa.dischtime, sa.hospital_expire_flag
)
-- Step 3: Calculate the requested cohort statistics
SELECT
    COUNT(DISTINCT cle.hadm_id) AS cohort_admissions,
    -- FIX: Use APPROX_QUANTILES to calculate the 25th percentile, as PERCENTILE_CONT is not supported directly as an aggregate in this BigQuery environment.
    ROUND(APPROX_QUANTILES(cle.critical_events_72hr, 100)[OFFSET(25)], 2) AS percentile_25_critical_events,
    ROUND(AVG(cle.critical_events_72hr), 2) AS mean_critical_events_per_admission,
    ROUND(AVG(DATETIME_DIFF(cle.dischtime, cle.admittime, HOUR) / 24.0), 2) AS mean_los_days,
    ROUND(AVG(cle.hospital_expire_flag) * 100, 2) AS mortality_percentage
FROM
    critical_lab_events AS cle;