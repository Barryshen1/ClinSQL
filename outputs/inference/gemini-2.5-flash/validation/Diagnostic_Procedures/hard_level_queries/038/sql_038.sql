WITH first_icu_stay AS (
    -- Identify the first ICU stay for each patient
    SELECT
        subject_id,
        hadm_id,
        stay_id,
        intime,
        outtime,
        los,
        ROW_NUMBER() OVER (PARTITION BY subject_id ORDER BY intime) as rn
    FROM
        `physionet-data.mimiciv_3_1_icu.icustays`
),
ich_hadms_with_diagnosis AS (
    -- Identify admissions with Intracranial Hemorrhage (ICH) diagnoses
    -- ICD-9 codes for ICH: 430 (Subarachnoid hem.), 431 (Intracerebral hem.), 432 (Other/unspecified intracranial hem.)
    -- ICD-10 codes for ICH: I60 (Nontraumatic subarachnoid hem.), I61 (Nontraumatic intracerebral hem.), I62 (Other/unspecified nontraumatic intracranial hem.)
    SELECT DISTINCT
        hadm_id
    FROM
        `physionet-data.mimiciv_3_1_hosp.diagnoses_icd`
    WHERE
        (icd_version = 9 AND icd_code LIKE '43[012]%')
        OR (icd_version = 10 AND icd_code LIKE 'I6[012]%')
),
ich_cohort_base AS (
    -- Filter for the target population: Male, 60-70 years old, first ICU stay, with ICH diagnosis
    SELECT
        fis.subject_id,
        fis.hadm_id,
        fis.stay_id,
        fis.intime,
        fis.los,
        adm.hospital_expire_flag
    FROM
        first_icu_stay fis
    INNER JOIN
        `physionet-data.mimiciv_3_1_hosp.patients` p
        ON fis.subject_id = p.subject_id
    INNER JOIN
        `physionet-data.mimiciv_3_1_hosp.admissions` adm
        ON fis.hadm_id = adm.hadm_id
    INNER JOIN
        ich_hadms_with_diagnosis ich -- Join to filter for admissions that have an ICH diagnosis
        ON fis.hadm_id = ich.hadm_id
    WHERE
        fis.rn = 1 -- Ensure it's the patient's first ICU stay
        AND p.gender = 'M'
        AND p.anchor_age BETWEEN 60 AND 70 -- Age filter: 60-70 years
),
ich_cohort_procedures AS (
    -- Calculate distinct procedure burden within the first 72 hours of ICU stay for the ICH cohort
    SELECT
        cb.stay_id,
        COUNT(DISTINCT pe.itemid) AS procedure_count_72h
    FROM
        ich_cohort_base cb
    LEFT JOIN
        `physionet-data.mimiciv_3_1_icu.procedureevents` pe
        ON cb.stay_id = pe.stay_id
        -- Filter procedures to be within the first 72 hours of ICU admission
       AND pe.starttime >= cb.intime
       AND pe.starttime < TIMESTAMP_ADD(cb.intime, INTERVAL 72 HOUR)
    GROUP BY
        cb.stay_id
),
ich_cohort_with_procedures AS ( -- Renamed for clarity from ich_cohort_final
    -- Combine base cohort data with their calculated procedure burden
    SELECT
        cb.subject_id,
        cb.hadm_id,
        cb.stay_id,
        cb.los,
        cb.hospital_expire_flag,
        COALESCE(icp.procedure_count_72h, 0) AS procedure_count_72h_final -- Use COALESCE to handle stays with 0 procedures (from LEFT JOIN)
    FROM
        ich_cohort_base cb
    LEFT JOIN
        ich_cohort_procedures icp
        ON cb.stay_id = icp.stay_id
),
ich_cohort_summary_calculated AS (
    -- Calculate summary statistics for the ICH cohort
    SELECT
        COUNT(DISTINCT stay_id) AS num_stays,
        -- Replaced PERCENTILE_DISC with PERCENTILE_CONT as PERCENTILE_DISC is not supported in BigQuery.
        -- PERCENTILE_CONT will return a continuous percentile value (likely a float).
        PERCENTILE_CONT(procedure_count_72h_final, 0.75) AS q3_procedure_burden,
        AVG(los) AS mean_icu_los_days,
        AVG(hospital_expire_flag) AS hospital_mortality_rate
    FROM
        ich_cohort_with_procedures
),
general_icu_population_summary AS (
    -- Calculate summary statistics for the general ICU population (all ICU stays)
    SELECT
        COUNT(DISTINCT s.stay_id) AS num_stays,
        AVG(s.los) AS mean_icu_los_days,
        AVG(a.hospital_expire_flag) AS hospital_mortality_rate
    FROM
        `physionet-data.mimiciv_3_1_icu.icustays` s
    INNER JOIN
        `physionet-data.mimiciv_3_1_hosp.admissions` a
        ON s.hadm_id = a.hadm_id
)
-- Final SELECT statement to present results for both cohorts
SELECT
    'ICH Cohort (Male, 60-70, First ICU Stay)' AS cohort_description,
    ics.num_stays AS num_patients_or_stays,
    ics.q3_procedure_burden,
    ics.mean_icu_los_days,
    ics.hospital_mortality_rate
FROM
    ich_cohort_summary_calculated ics

UNION ALL

SELECT
    'General ICU Population' AS cohort_description,
    gips.num_stays AS num_patients_or_stays,
    NULL AS q3_procedure_burden, -- Not requested for general population
    gips.mean_icu_los_days,
    gips.hospital_mortality_rate
FROM
    general_icu_population_summary gips;