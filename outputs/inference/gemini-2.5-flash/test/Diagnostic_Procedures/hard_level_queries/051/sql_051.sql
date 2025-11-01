WITH sepsis_admissions AS (
    SELECT DISTINCT hadm_id
    FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd`
    WHERE (
        (icd_version = 10 AND icd_code LIKE 'A40%') OR -- Streptococcus sepsis, and other specific bacterial sepsis
        (icd_version = 10 AND icd_code LIKE 'A41%') OR -- Other sepsis (e.g., A41.9 Unspecified sepsis)
        (icd_version = 10 AND icd_code LIKE 'R652%')   -- Severe sepsis / septic shock (e.g., R65.20, R65.21)
    )
),
-- CTE to define the patient cohort based on age, gender, ICU stay, and sepsis diagnosis
cohort_icustays AS (
    SELECT
        pat.subject_id,
        adm.hadm_id,
        icu.stay_id,
        icu.intime,
        icu.outtime,
        adm.hospital_expire_flag
    FROM `physionet-data.mimiciv_3_1_hosp.patients` pat
    INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` adm
        ON pat.subject_id = adm.subject_id
    INNER JOIN `physionet-data.mimiciv_3_1_icu.icustays` icu
        ON adm.hadm_id = icu.hadm_id
    INNER JOIN sepsis_admissions sa
        ON adm.hadm_id = sa.hadm_id
    WHERE
        pat.gender = 'M'
        AND pat.anchor_age BETWEEN 90 AND 100
),
-- CTE to count distinct diagnostic events (lab and microbiology) within the first 24 hours for each ICU stay
diagnostic_events_24h_per_stay AS (
    SELECT
        cs.stay_id,
        -- Count distinct lab events (identified by labevent_id) within the 24h window
        COUNT(DISTINCT le.labevent_id) AS num_lab_events,
        -- Count distinct microbiology events (identified by microevent_id) within the 24h window
        COUNT(DISTINCT me.microevent_id) AS num_micro_events
    FROM cohort_icustays cs
    LEFT JOIN `physionet-data.mimiciv_3_1_hosp.labevents` le
        ON cs.subject_id = le.subject_id
        AND cs.hadm_id = le.hadm_id
        AND le.charttime >= cs.intime
        AND le.charttime <= DATETIME_ADD(cs.intime, INTERVAL 24 HOUR)
    LEFT JOIN `physionet-data.mimiciv_3_1_hosp.microbiologyevents` me
        ON cs.subject_id = me.subject_id
        AND cs.hadm_id = me.hadm_id
        AND me.charttime >= cs.intime
        AND me.charttime <= DATETIME_ADD(cs.intime, INTERVAL 24 HOUR)
    GROUP BY cs.stay_id
),
-- CTE to combine the cohort information with the calculated 24h diagnostic utilization
total_diagnostic_utilization_per_stay AS (
    SELECT
        cs.subject_id,
        cs.hadm_id,
        cs.stay_id,
        cs.intime,
        cs.outtime,
        cs.hospital_expire_flag,
        -- Sum of distinct lab and micro events for overall diagnostic utilization
        COALESCE(de.num_lab_events, 0) + COALESCE(de.num_micro_events, 0) AS diagnostic_utilization_24h
    FROM cohort_icustays cs
    LEFT JOIN diagnostic_events_24h_per_stay de
        ON cs.stay_id = de.stay_id
)
-- Final aggregation to calculate all requested metrics
SELECT
    COUNT(DISTINCT tdu.hadm_id) AS Admissions,
    COUNT(DISTINCT tdu.stay_id) AS ICUMeetsCriteria,
    ROUND(AVG(CAST(tdu.hospital_expire_flag AS BIGNUMERIC)) * 100, 2) AS InHospitalMortalityPercent,
    ROUND(AVG(DATETIME_DIFF(tdu.outtime, tdu.intime, HOUR) / 24.0), 2) AS AverageICULOSDays,
    ROUND(STDDEV(tdu.diagnostic_utilization_24h), 2) AS SDOfDiagnosticUtilization24h,
    -- Corrected PERCENTILE_CONT syntax for BigQuery by adding OVER()
    ROUND(PERCENTILE_CONT(tdu.diagnostic_utilization_24h, 0.75) OVER(), 2) AS P75OfDiagnosticUtilization24h,
    ROUND(PERCENTILE_CONT(tdu.diagnostic_utilization_24h, 0.95) OVER(), 2) AS P95OfDiagnosticUtilization24h
FROM total_diagnostic_utilization_per_stay tdu;