WITH cohort AS (
    SELECT 
        adm.subject_id, 
        adm.hadm_id, 
        adm.admittime, 
        adm.dischtime,
        -- Calculate length of stay in days
        DATETIME_DIFF(adm.dischtime, adm.admittime, DAY) AS los_days,
        -- Check if ICU stay occurred
        CASE WHEN icu.stay_id IS NOT NULL THEN 1 ELSE 0 END AS icu_used
    FROM `physionet-data.mimiciv_3_1_hosp.admissions` adm
    INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` pat
        ON adm.subject_id = pat.subject_id
    INNER JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` diag
        ON adm.hadm_id = diag.hadm_id
    LEFT JOIN `physionet-data.mimiciv_3_1_icu.icustays` icu
        ON adm.hadm_id = icu.hadm_id
    WHERE 
        pat.gender = 'F'
        AND pat.anchor_age BETWEEN 38 AND 48
        AND diag.icd_version = 10
        AND diag.icd_code LIKE 'N17%'
),

los_groups AS (
    SELECT
        subject_id,
        hadm_id,
        icu_used,
        CASE 
            WHEN los_days BETWEEN 1 AND 4 THEN '1-4'
            WHEN los_days BETWEEN 5 AND 7 THEN '5-7'
            ELSE 'Other'
        END AS los_group
    FROM cohort
    WHERE los_days BETWEEN 1 AND 7  -- Only include stays 1-7 days
),

lab_counts AS (
    SELECT 
        lg.subject_id,
        lg.hadm_id,
        lg.icu_used,
        lg.los_group,
        COUNT(DISTINCT le.labevent_id) AS num_lab_events
    FROM los_groups lg
    LEFT JOIN `physionet-data.mimiciv_3_1_hosp.labevents` le
        ON lg.hadm_id = le.hadm_id
    GROUP BY lg.subject_id, lg.hadm_id, lg.icu_used, lg.los_group
)

SELECT 
    icu_used,
    los_group,
    AVG(num_lab_events) AS mean_diagnostics,
    MIN(num_lab_events) AS min_diagnostics,
    MAX(num_lab_events) AS max_diagnostics,
    COUNT(*) AS num_admissions
FROM lab_counts
GROUP BY icu_used, los_group
ORDER BY icu_used, los_group;