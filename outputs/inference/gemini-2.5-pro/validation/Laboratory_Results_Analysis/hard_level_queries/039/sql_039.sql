WITH
-- CTE 1: Identify all admissions for primary pneumonia
pneumonia_cohort AS (
    SELECT
        adm.subject_id,
        adm.hadm_id,
        adm.admittime,
        adm.dischtime,
        adm.hospital_expire_flag,
        (EXTRACT(YEAR FROM adm.admittime) - pat.anchor_year + pat.anchor_age) AS age_at_admission
    FROM `physionet-data.mimiciv_3_1_hosp.admissions` AS adm
    INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` AS pat
        ON adm.subject_id = pat.subject_id
    INNER JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` AS dx
        ON adm.hadm_id = dx.hadm_id
    WHERE
        dx.seq_num = 1 -- Primary diagnosis
        AND (
            -- ICD-9 codes for pneumonia (480-486)
            (dx.icd_version = 9 AND SUBSTR(dx.icd_code, 1, 3) BETWEEN '480' AND '486')
            OR
            -- ICD-10 codes for pneumonia (J12-J18)
            (dx.icd_version = 10 AND SUBSTR(dx.icd_code, 1, 3) BETWEEN 'J12' AND 'J18')
        )
),

-- CTE 2: Filter the cohort for males aged 60-70
cohort_admissions AS (
    SELECT
        *
    FROM pneumonia_cohort
    WHERE
        age_at_admission BETWEEN 60 AND 70
        AND subject_id IN (SELECT subject_id FROM `physionet-data.mimiciv_3_1_hosp.patients` WHERE gender = 'M')
),

-- CTE 3: Calculate the 72-hour lab instability score for each cohort admission
lab_instability_scores AS (
    SELECT
        c.hadm_id,
        COUNT(le.labevent_id) AS lab_instability_score
    FROM cohort_admissions AS c
    INNER JOIN `physionet-data.mimiciv_3_1_hosp.labevents` AS le
        ON c.hadm_id = le.hadm_id
    WHERE
        le.flag = 'abnormal'
        AND le.charttime BETWEEN c.admittime AND DATETIME_ADD(c.admittime, INTERVAL 72 HOUR)
    GROUP BY c.hadm_id
),

-- CTE 4: Identify all critical events (vasopressors, ventilation, RRT) across all patients
critical_events_all AS (
    -- Vasopressors from inputevents
    SELECT hadm_id FROM `physionet-data.mimiciv_3_1_icu.inputevents`
    WHERE itemid IN (
        221906, -- Norepinephrine
        221289, -- Epinephrine
        222315, -- Vasopressin
        221662, -- Dopamine
        221749  -- Phenylephrine
    ) AND statusdescription != 'Rewritten' -- Exclude erroneous entries
    UNION ALL
    -- Invasive Ventilation from procedureevents
    SELECT hadm_id FROM `physionet-data.mimiciv_3_1_icu.procedureevents`
    WHERE itemid = 225792 -- Invasive Ventilation
    UNION ALL
    -- Renal Replacement Therapy from procedureevents
    SELECT hadm_id FROM `physionet-data.mimiciv_3_1_icu.procedureevents`
    WHERE itemid IN (
        225802, -- Dialysis - CRRT
        225803, -- Dialysis - CVVHD
        225805  -- Dialysis - IHD
    )
),

-- CTE 5: Count total critical events per admission for all patients
event_counts_all AS (
    SELECT
        hadm_id,
        COUNT(*) AS num_critical_events
    FROM critical_events_all
    GROUP BY hadm_id
),

-- CTE 6: Calculate LOS and critical event frequency for ALL hospital admissions
all_patient_stats AS (
    SELECT
        adm.hadm_id,
        DATETIME_DIFF(adm.dischtime, adm.admittime, HOUR) / 24.0 AS los_days,
        COALESCE(ec.num_critical_events, 0)
            / GREATEST(0.01, DATETIME_DIFF(adm.dischtime, adm.admittime, HOUR) / 24.0)
            AS critical_event_freq
    FROM `physionet-data.mimiciv_3_1_hosp.admissions` AS adm
    LEFT JOIN event_counts_all AS ec
        ON adm.hadm_id = ec.hadm_id
    WHERE adm.dischtime IS NOT NULL AND adm.admittime IS NOT NULL -- Ensure LOS can be calculated
),

-- CTE 7: Calculate final aggregated metrics for the specified cohort
cohort_final_stats AS (
    SELECT
        APPROX_QUANTILES(COALESCE(lis.lab_instability_score, 0), 100)[OFFSET(75)] AS p75_lab_instability_score,
        AVG(aps.critical_event_freq) AS mean_critical_event_freq_cohort,
        AVG(aps.los_days) AS mean_los_cohort,
        AVG(CAST(c.hospital_expire_flag AS FLOAT64)) AS mortality_rate_cohort
    FROM cohort_admissions AS c
    LEFT JOIN lab_instability_scores AS lis ON c.hadm_id = lis.hadm_id
    LEFT JOIN all_patient_stats AS aps ON c.hadm_id = aps.hadm_id
),

-- CTE 8: Calculate the mean critical event frequency for the comparison group (all inpatients)
all_inpatients_final_stats AS (
    SELECT
        AVG(critical_event_freq) AS mean_critical_event_freq_all
    FROM all_patient_stats
)

-- Final SELECT statement to combine and present the results
SELECT
    cohort.p75_lab_instability_score,
    cohort.mean_critical_event_freq_cohort,
    all_inpatients.mean_critical_event_freq_all,
    cohort.mean_los_cohort,
    cohort.mortality_rate_cohort
FROM cohort_final_stats AS cohort
CROSS JOIN all_inpatients_final_stats AS all_inpatients;