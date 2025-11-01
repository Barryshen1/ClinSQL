WITH copd_hadms AS (
    -- Find all hospital admissions with a diagnosis of COPD with acute exacerbation
    SELECT DISTINCT
        hadm_id
    FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd`
    WHERE
        -- J44.1: Chronic obstructive pulmonary disease with acute exacerbation (ICD-10)
        -- 491.21: Obstructive chronic bronchitis with (acute) exacerbation (ICD-9)
        (icd_version = 10 AND icd_code = 'J441')
        OR (icd_version = 9 AND icd_code = '49121')
),

base_stays AS (
    -- Create a base cohort of all ICU stays for male patients aged 88-98
    -- and flag them if they have a COPD exacerbation diagnosis
    SELECT
        icu.subject_id,
        icu.hadm_id,
        icu.stay_id,
        icu.intime,
        icu.los,
        adm.hospital_expire_flag,
        -- Flag for COPD exacerbation
        (icu.hadm_id IN (SELECT hadm_id FROM copd_hadms)) AS is_copd_exacerbation_stay
    FROM `physionet-data.mimiciv_3_1_icu.icustays` AS icu
    INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` AS pat
        ON icu.subject_id = pat.subject_id
    INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` AS adm
        ON icu.hadm_id = adm.hadm_id
    WHERE
        pat.gender = 'M'
        AND pat.anchor_age BETWEEN 88 AND 98
),

copd_cohort_proc_counts AS (
    -- For the COPD cohort, count distinct procedures within the first 72 hours of each ICU stay
    SELECT
        bst.stay_id,
        COUNT(DISTINCT pe.itemid) AS distinct_procedure_count
    FROM base_stays AS bst
    INNER JOIN `physionet-data.mimiciv_3_1_icu.procedureevents` AS pe
        ON bst.stay_id = pe.stay_id
    WHERE
        bst.is_copd_exacerbation_stay IS TRUE
        -- Filter procedures to the first 72 hours of the ICU stay
        AND pe.starttime <= TIMESTAMP_ADD(bst.intime, INTERVAL 72 HOUR)
    GROUP BY
        bst.stay_id
),

copd_stats AS (
    -- Calculate all required metrics for the COPD cohort
    SELECT
        APPROX_QUANTILES(COALESCE(proc.distinct_procedure_count, 0), 100)[OFFSET(75)] AS p75_distinct_procedures_72h,
        AVG(bst.los) AS mean_icu_los_copd,
        AVG(CAST(bst.hospital_expire_flag AS FLOAT64)) AS in_hospital_mortality_copd
    FROM base_stays AS bst
    LEFT JOIN copd_cohort_proc_counts AS proc
        ON bst.stay_id = proc.stay_id
    WHERE bst.is_copd_exacerbation_stay IS TRUE
),

control_stats AS (
    -- Calculate comparative metrics for the age-matched control cohort
    SELECT
        AVG(los) AS mean_icu_los_control,
        AVG(CAST(hospital_expire_flag AS FLOAT64)) AS in_hospital_mortality_control
    FROM base_stays
    WHERE is_copd_exacerbation_stay IS FALSE
)

-- Final result combining stats from both cohorts
SELECT
    copd.p75_distinct_procedures_72h,
    copd.mean_icu_los_copd,
    copd.in_hospital_mortality_copd,
    ctrl.mean_icu_los_control,
    ctrl.in_hospital_mortality_control
FROM copd_stats AS copd
CROSS JOIN control_stats AS ctrl;