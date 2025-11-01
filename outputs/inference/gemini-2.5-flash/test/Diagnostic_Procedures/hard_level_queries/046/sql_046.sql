WITH first_icu_stays AS (
    SELECT
        s.subject_id,
        s.hadm_id,
        s.stay_id,
        s.intime,
        s.outtime,
        ROW_NUMBER() OVER (PARTITION BY s.subject_id ORDER BY s.intime) AS rn
    FROM
        `physionet-data.mimiciv_3_1_icu.icustays` s
),
-- Step 2: Get admission details (LOS, mortality)
admissions_data AS (
    SELECT
        adm.subject_id,
        adm.hadm_id,
        adm.admittime,
        adm.dischtime,
        DATETIME_DIFF(adm.dischtime, adm.admittime, HOUR) AS hospital_los_hours, -- Calculate LOS in hours
        adm.hospital_expire_flag
    FROM
        `physionet-data.mimiciv_3_1_hosp.admissions` adm
),
-- Step 3: Get patient demographics
patients_demographics AS (
    SELECT
        p.subject_id,
        p.gender,
        p.anchor_age
    FROM
        `physionet-data.mimiciv_3_1_hosp.patients` p
),
-- Step 4: Define the ARDS Cohort (first ICU stay, female, 37-47, ARDS diagnosis)
cohort_base AS (
    SELECT DISTINCT
        fis.subject_id,
        fis.hadm_id,
        fis.stay_id,
        fis.intime,
        fis.outtime
    FROM
        first_icu_stays fis
    JOIN
        admissions_data ad ON fis.subject_id = ad.subject_id AND fis.hadm_id = ad.hadm_id
    JOIN
        patients_demographics pd ON fis.subject_id = pd.subject_id
    JOIN
        `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` di ON fis.subject_id = di.subject_id AND fis.hadm_id = di.hadm_id
    WHERE
        fis.rn = 1 -- Limit to first ICU stay for each patient
        AND pd.gender = 'F'
        AND pd.anchor_age BETWEEN 37 AND 47
        AND di.icd_code = 'J80' -- ICD-10 code for Acute respiratory distress syndrome (ARDS)
        AND di.icd_version = 10
),
-- Step 5: Calculate distinct procedure counts for the ARDS cohort within the first 72 hours of ICU stay
cohort_proc_counts AS (
    SELECT
        cb.subject_id,
        cb.hadm_id,
        cb.stay_id,
        COUNT(DISTINCT pi.icd_code) AS distinct_procedures_72h
    FROM
        cohort_base cb
    LEFT JOIN
        `physionet-data.mimiciv_3_1_hosp.procedures_icd` pi
        ON cb.subject_id = pi.subject_id
        AND cb.hadm_id = pi.hadm_id
    WHERE
        -- Procedures must be on or after the ICU intime date, and strictly before the date 72 hours after intime.
        -- This covers procedures within the first 72 hours when chartdate is only a DATE.
        DATE(pi.chartdate) >= DATE(cb.intime)
        AND DATE(pi.chartdate) < DATE(TIMESTAMP_ADD(cb.intime, INTERVAL 72 HOUR))
    GROUP BY
        cb.subject_id, cb.hadm_id, cb.stay_id
),
-- Step 6: Define the comparison group (All ICU Patients, first stay)
all_icu_base AS (
    SELECT
        fis.subject_id,
        fis.hadm_id,
        fis.stay_id,
        fis.intime,
        fis.outtime
    FROM
        first_icu_stays fis
    WHERE
        fis.rn = 1 -- Limit to first ICU stay for each patient
),
-- Step 7: Calculate distinct procedure counts for all ICU patients (first stay) within the first 72 hours
all_icu_proc_counts AS (
    SELECT
        ab.subject_id,
        ab.hadm_id,
        ab.stay_id,
        COUNT(DISTINCT pi.icd_code) AS distinct_procedures_72h
    FROM
        all_icu_base ab
    LEFT JOIN
        `physionet-data.mimiciv_3_1_hosp.procedures_icd` pi
        ON ab.subject_id = pi.subject_id
        AND ab.hadm_id = pi.hadm_id
    WHERE
        -- Procedures must be on or after the ICU intime date, and strictly before the date 72 hours after intime.
        DATE(pi.chartdate) >= DATE(ab.intime)
        AND DATE(pi.chartdate) < DATE(TIMESTAMP_ADD(ab.intime, INTERVAL 72 HOUR))
    GROUP BY
        ab.subject_id, ab.hadm_id, ab.stay_id
),
-- Step 8: Combine data for ARDS cohort to calculate metrics at the patient/stay level
cohort_combined_data AS (
    SELECT
        cb.subject_id,
        cb.hadm_id,
        cb.stay_id,
        COALESCE(cpc.distinct_procedures_72h, 0) AS distinct_procedures_72h, -- Coalesce to 0 for patients with no procedures during the window
        ad.hospital_los_hours,
        ad.hospital_expire_flag
    FROM
        cohort_base cb
    LEFT JOIN
        cohort_proc_counts cpc ON cb.subject_id = cpc.subject_id AND cb.hadm_id = cpc.hadm_id AND cb.stay_id = cpc.stay_id
    JOIN
        admissions_data ad ON cb.subject_id = ad.subject_id AND cb.hadm_id = ad.hadm_id
    WHERE
        ad.dischtime IS NOT NULL -- Exclude ongoing stays for valid LOS calculation
),
-- Step 9: Aggregate metrics for the ARDS cohort
cohort_metrics AS (
    SELECT
        'ARDS Cohort' AS group_name,
        MIN(cd.distinct_procedures_72h) AS min_diagnostic_utilization,
        PERCENTILE_CONT(cd.distinct_procedures_72h, 0.75) OVER () AS p75_diagnostic_utilization,
        PERCENTILE_CONT(cd.distinct_procedures_72h, 0.90) OVER () AS p90_diagnostic_utilization,
        AVG(cd.hospital_los_hours) AS mean_hospital_los_hours,
        SAFE_DIVIDE(SUM(cd.hospital_expire_flag), COUNT(cd.hospital_expire_flag)) * 100.0 AS in_hospital_mortality_percent
    FROM
        cohort_combined_data cd
),
-- Step 10: Combine data for all ICU patients to calculate metrics at the patient/stay level
all_icu_combined_data AS (
    SELECT
        ab.subject_id,
        ab.hadm_id,
        ab.stay_id,
        COALESCE(apc.distinct_procedures_72h, 0) AS distinct_procedures_72h, -- Coalesce to 0 for patients with no procedures during the window
        ad.hospital_los_hours,
        ad.hospital_expire_flag
    FROM
        all_icu_base ab
    LEFT JOIN
        all_icu_proc_counts apc ON ab.subject_id = apc.subject_id AND ab.hadm_id = apc.hadm_id AND ab.stay_id = apc.stay_id
    JOIN
        admissions_data ad ON ab.subject_id = ad.subject_id AND ab.hadm_id = ad.hadm_id
    WHERE
        ad.dischtime IS NOT NULL -- Exclude ongoing stays for valid LOS calculation
),
-- Step 11: Aggregate metrics for all ICU patients (first stay)
all_icu_metrics AS (
    SELECT
        'All ICU (First Stay)' AS group_name,
        MIN(acd.distinct_procedures_72h) AS min_diagnostic_utilization,
        PERCENTILE_CONT(acd.distinct_procedures_72h, 0.75) OVER () AS p75_diagnostic_utilization,
        PERCENTILE_CONT(acd.distinct_procedures_72h, 0.90) OVER () AS p90_diagnostic_utilization,
        AVG(acd.hospital_los_hours) AS mean_hospital_los_hours,
        SAFE_DIVIDE(SUM(acd.hospital_expire_flag), COUNT(acd.hospital_expire_flag)) * 100.0 AS in_hospital_mortality_percent
    FROM
        all_icu_combined_data acd
)
-- Combine and present the results
SELECT * FROM cohort_metrics
UNION ALL
SELECT * FROM all_icu_metrics;