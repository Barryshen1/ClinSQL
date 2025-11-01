WITH
-- Step 1: Define the cohort of interest: female admissions, aged 43-53, with a sepsis diagnosis.
sepsis_admissions AS (
    SELECT DISTINCT
        adm.subject_id,
        adm.hadm_id,
        adm.admittime,
        adm.dischtime,
        adm.hospital_expire_flag
    FROM
        `physionet-data.mimiciv_3_1_hosp.admissions` AS adm
    INNER JOIN
        `physionet-data.mimiciv_3_1_hosp.patients` AS pat
            ON adm.subject_id = pat.subject_id
    INNER JOIN
        `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` AS dx
            ON adm.hadm_id = dx.hadm_id
    WHERE
        pat.gender = 'F'
        AND pat.anchor_age BETWEEN 43 AND 53
        AND (
            -- Sepsis-related ICD-9 codes
            (dx.icd_version = 9 AND (
                dx.icd_code LIKE '99591%' -- Sepsis
                OR dx.icd_code LIKE '99592%' -- Severe sepsis
                OR dx.icd_code LIKE '78552%' -- Septic shock
                OR dx.icd_code LIKE '038%'   -- Septicemia
            ))
            OR
            -- Sepsis-related ICD-10 codes
            (dx.icd_version = 10 AND (
                dx.icd_code LIKE 'A40%'     -- Streptococcal sepsis
                OR dx.icd_code LIKE 'A41%'     -- Other sepsis
                OR dx.icd_code LIKE 'R65.2%'   -- Severe sepsis
            ))
        )
),

-- Step 2: Calculate the instability score (critical lab events) and other metrics for each admission in the cohort.
cohort_scores AS (
    SELECT
        sa.hadm_id,
        -- LOS in days
        DATETIME_DIFF(sa.dischtime, sa.admittime, HOUR) / 24.0 AS los,
        sa.hospital_expire_flag,
        -- Count of abnormal labs in the first 72 hours
        COUNT(le.labevent_id) AS critical_lab_events
    FROM
        sepsis_admissions AS sa
    LEFT JOIN -- LEFT JOIN to include admissions with 0 critical labs
        `physionet-data.mimiciv_3_1_hosp.labevents` AS le
            ON sa.hadm_id = le.hadm_id
            AND le.flag = 'abnormal'
            AND le.charttime BETWEEN sa.admittime AND DATETIME_ADD(sa.admittime, INTERVAL 72 HOUR)
    GROUP BY
        sa.hadm_id, sa.admittime, sa.dischtime, sa.hospital_expire_flag
),

-- Step 3: Calculate the general (all-admission) baseline statistics for comparison.
general_stats AS (
    SELECT
        -- General Mean LOS
        (
            SELECT AVG(DATETIME_DIFF(dischtime, admittime, HOUR) / 24.0)
            FROM `physionet-data.mimiciv_3_1_hosp.admissions`
        ) AS general_mean_los,
        -- General Mortality Rate
        (
            SELECT AVG(hospital_expire_flag)
            FROM `physionet-data.mimiciv_3_1_hosp.admissions`
        ) AS general_mortality,
        -- General Mean Critical Events per admission
        (
            (
                SELECT COUNT(le.labevent_id)
                FROM `physionet-data.mimiciv_3_1_hosp.admissions` adm
                INNER JOIN `physionet-data.mimiciv_3_1_hosp.labevents` le
                    ON adm.hadm_id = le.hadm_id
                WHERE
                    le.flag = 'abnormal'
                    AND le.charttime BETWEEN adm.admittime AND DATETIME_ADD(adm.admittime, INTERVAL 72 HOUR)
            )
            /
            (SELECT COUNT(hadm_id) FROM `physionet-data.mimiciv_3_1_hosp.admissions`)
        ) AS general_mean_critical_events
)


-- Step 4: Aggregate the cohort scores and combine with the general stats for the final report.
SELECT
    -- Cohort-specific statistics
    APPROX_QUANTILES(cs.critical_lab_events, 100)[OFFSET(25)] AS cohort_p25_instability_score,
    AVG(cs.critical_lab_events) AS cohort_mean_critical_events,
    AVG(cs.los) AS cohort_mean_los,
    AVG(cs.hospital_expire_flag) AS cohort_mortality_rate,
    -- General database statistics for comparison
    gs.general_mean_critical_events,
    gs.general_mean_los,
    gs.general_mortality
FROM
    cohort_scores AS cs,
    general_stats AS gs
GROUP BY
    gs.general_mean_critical_events,
    gs.general_mean_los,
    gs.general_mortality;