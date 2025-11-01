WITH ich_cohort_admissions AS (
    -- Step 1: Identify admissions for female patients aged 50-60 with Intracranial Hemorrhage (ICH)
    SELECT DISTINCT
        ad.subject_id,
        ad.hadm_id,
        ad.admittime,
        ad.dischtime,
        ad.hospital_expire_flag
    FROM
        `physionet-data.mimiciv_3_1_hosp.admissions` ad
    JOIN
        `physionet-data.mimiciv_3_1_hosp.patients` p
        ON ad.subject_id = p.subject_id
    JOIN
        `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` di
        ON ad.hadm_id = di.hadm_id
    WHERE
        p.gender = 'F'
        AND p.anchor_age BETWEEN 50 AND 60
        -- ICD-10 codes for Intracranial Hemorrhage (I60-I62)
        AND (di.icd_code LIKE 'I60%' OR di.icd_code LIKE 'I61%' OR di.icd_code LIKE 'I62%')
),
ich_icu_stays AS (
    -- Step 2: Extract relevant ICU stays for the ICH cohort
    SELECT
        ica.subject_id,
        ica.hadm_id,
        ica.admittime,
        ica.dischtime,
        ica.hospital_expire_flag,
        icu.stay_id,
        icu.intime
    FROM
        ich_cohort_admissions ica
    JOIN
        `physionet-data.mimiciv_3_1_icu.icustays` icu
        ON ica.subject_id = icu.subject_id AND ica.hadm_id = icu.hadm_id
),
ich_proc_72h AS (
    -- Step 3: Calculate procedure counts in the initial 72 hours of ICU stay for the ICH cohort
    SELECT
        iis.stay_id,
        COUNT(DISTINCT pe.itemid) AS num_procedures_72h
    FROM
        ich_icu_stays iis
    JOIN
        `physionet-data.mimiciv_3_1_icu.procedureevents` pe
        ON iis.stay_id = pe.stay_id
    WHERE
        pe.starttime BETWEEN iis.intime AND TIMESTAMP_ADD(iis.intime, INTERVAL 72 HOUR)
    GROUP BY
        iis.stay_id
),
ich_full_data_for_stats AS (
    -- Step 4: Prepare a combined dataset for ICH cohort statistics (including procedure counts)
    SELECT
        iis.subject_id,
        iis.hadm_id,
        iis.stay_id,
        iis.admittime,
        iis.dischtime,
        iis.hospital_expire_flag,
        COALESCE(ip72.num_procedures_72h, 0) AS num_procedures_72h
    FROM
        ich_icu_stays iis
    LEFT JOIN -- Use LEFT JOIN to include stays with no procedures in the first 72 hours
        ich_proc_72h ip72
        ON iis.stay_id = ip72.stay_id
),
ich_final_aggregated_stats AS (
    -- Step 5: Aggregate all statistics for the ICH cohort
    SELECT
        'ICH Cohort' AS cohort_type,
        COUNT(DISTINCT t1.stay_id) OVER() AS num_icu_stays, -- Added OVER()
        COUNT(DISTINCT t1.hadm_id) OVER() AS num_hospital_admissions, -- Added OVER()
        PERCENTILE_CONT(t1.num_procedures_72h, 0.25) OVER() AS proc_25th_perc,
        PERCENTILE_CONT(t1.num_procedures_72h, 0.50) OVER() AS proc_50th_perc,
        PERCENTILE_CONT(t1.num_procedures_72h, 0.90) OVER() AS proc_90th_perc,
        MAX(t1.num_procedures_72h) OVER() AS proc_max,
        AVG(DATE_DIFF(t1.dischtime, t1.admittime, DAY)) OVER() AS avg_hospital_los,
        -- Calculate mortality rate correctly across distinct hospital admissions
        (SELECT
            CAST(SUM(t_mort.hospital_expire_flag) AS BIGNUMERIC) / COUNT(t_mort.hadm_id)
         FROM (SELECT DISTINCT hadm_id, hospital_expire_flag FROM ich_full_data_for_stats) t_mort
        ) AS mortality_rate
    FROM
        ich_full_data_for_stats t1
    QUALIFY ROW_NUMBER() OVER(ORDER BY 1) = 1 -- Ensure single row output for global aggregates
),
general_icu_cohort_admissions AS (
    -- Step 6: Identify admissions for the general ICU cohort (female, 50-60, no ICH filter)
    SELECT DISTINCT
        ad.subject_id,
        ad.hadm_id,
        ad.admittime,
        ad.dischtime,
        ad.hospital_expire_flag
    FROM
        `physionet-data.mimiciv_3_1_hosp.admissions` ad
    JOIN
        `physionet-data.mimiciv_3_1_hosp.patients` p
        ON ad.subject_id = p.subject_id
    WHERE
        p.gender = 'F'
        AND p.anchor_age BETWEEN 50 AND 60
),
general_icu_stays AS (
    -- Step 7: Extract relevant ICU stays for the general ICU cohort
    SELECT
        gica.subject_id,
        gica.hadm_id,
        gica.admittime,
        gica.dischtime,
        gica.hospital_expire_flag,
        icu.stay_id
    FROM
        general_icu_cohort_admissions gica
    JOIN
        `physionet-data.mimiciv_3_1_icu.icustays` icu
        ON gica.subject_id = icu.subject_id AND gica.hadm_id = icu.hadm_id
),
general_icu_final_aggregated_stats AS (
    -- Step 8: Aggregate statistics for the general ICU cohort
    SELECT
        'General ICU Cohort (Female, 50-60)' AS cohort_type,
        COUNT(DISTINCT t1.stay_id) OVER() AS num_icu_stays, -- Added OVER()
        COUNT(DISTINCT t1.hadm_id) OVER() AS num_hospital_admissions, -- Added OVER()
        NULL AS proc_25th_perc, -- Not requested for this cohort
        NULL AS proc_50th_perc,
        NULL AS proc_90th_perc,
        NULL AS proc_max,
        AVG(DATE_DIFF(t1.dischtime, t1.admittime, DAY)) OVER() AS avg_hospital_los,
        -- Calculate mortality rate correctly across distinct hospital admissions
        (SELECT
            CAST(SUM(t_mort.hospital_expire_flag) AS BIGNUMERIC) / COUNT(t_mort.hadm_id)
         FROM (SELECT DISTINCT hadm_id, hospital_expire_flag FROM general_icu_stays) t_mort
        ) AS mortality_rate
    FROM
        general_icu_stays t1
    QUALIFY ROW_NUMBER() OVER(ORDER BY 1) = 1 -- Ensure single row output for global aggregates
)
-- Step 9: Final union of results
SELECT
    cohort_type,
    num_icu_stays,
    num_hospital_admissions,
    proc_25th_perc,
    proc_50th_perc,
    proc_90th_perc,
    proc_max,
    avg_hospital_los,
    mortality_rate
FROM
    ich_final_aggregated_stats

UNION ALL

SELECT
    cohort_type,
    num_icu_stays,
    num_hospital_admissions,
    proc_25th_perc,
    proc_50th_perc,
    proc_90th_perc,
    proc_max,
    avg_hospital_los,
    mortality_rate
FROM
    general_icu_final_aggregated_stats;