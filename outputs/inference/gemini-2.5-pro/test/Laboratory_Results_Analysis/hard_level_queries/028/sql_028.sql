with Intracranial Hemorrhage (ICH),
-- stratifies them by lab instability in the first 72 hours, reports mortality and LOS by quintile,
-- and compares their average lab instability to an age-matched control group.

WITH
-- Step 1: Define the relevant ICD codes for Intracranial Hemorrhage (ICH)
ich_codes AS (
    SELECT icd_code, icd_version
    FROM `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses`
    WHERE
        -- Common ICD-9 codes for ICH
        (icd_version = 9 AND SUBSTR(icd_code, 1, 3) IN ('430', '431', '432')) OR
        -- Common ICD-10 codes for ICH
        (icd_version = 10 AND SUBSTR(icd_code, 1, 3) IN ('I60', 'I61', 'I62'))
),

-- Step 2: Create a base cohort of female patients aged 74-84 and flag them for ICH
base_cohort AS (
    SELECT
        p.subject_id,
        a.hadm_id,
        a.admittime,
        a.hospital_expire_flag,
        DATETIME_DIFF(a.dischtime, a.admittime, DAY) AS los_days,
        -- Flag is 1 if the admission has any ICH diagnosis, 0 otherwise
        MAX(CASE WHEN dx.hadm_id IS NOT NULL THEN 1 ELSE 0 END) AS is_ich_patient
    FROM `physionet-data.mimiciv_3_1_hosp.patients` AS p
    INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` AS a
        ON p.subject_id = a.subject_id
    -- Left join to see which admissions have an ICH diagnosis
    LEFT JOIN (
        SELECT DISTINCT hadm_id
        FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd`
        WHERE (icd_code, icd_version) IN (SELECT icd_code, icd_version FROM ich_codes)
    ) AS dx
        ON a.hadm_id = dx.hadm_id
    WHERE
        p.gender = 'F'
        AND p.anchor_age BETWEEN 74 AND 84
    GROUP BY
        p.subject_id, a.hadm_id, a.admittime, a.dischtime, a.hospital_expire_flag
),

-- Step 3: Count distinct abnormal labs in the first 72 hours for each admission in our cohort
abnormal_labs_count AS (
    SELECT
        le.hadm_id,
        COUNT(DISTINCT le.itemid) AS distinct_abnormal_labs
    FROM `physionet-data.mimiciv_3_1_hosp.labevents` AS le
    INNER JOIN base_cohort AS bc
        ON le.hadm_id = bc.hadm_id
    WHERE
        le.flag = 'abnormal'
        AND le.charttime BETWEEN bc.admittime AND DATETIME_ADD(bc.admittime, INTERVAL 72 HOUR)
    GROUP BY le.hadm_id
),

-- Step 4: Combine base cohort data with the calculated lab instability scores
patient_level_data AS (
    SELECT
        bc.hadm_id,
        bc.is_ich_patient,
        bc.hospital_expire_flag,
        bc.los_days,
        -- If no abnormal labs were found, the count is 0
        COALESCE(alc.distinct_abnormal_labs, 0) AS distinct_abnormal_labs
    FROM base_cohort AS bc
    LEFT JOIN abnormal_labs_count AS alc
        ON bc.hadm_id = alc.hadm_id
),

-- Step 5: Stratify the ICH patient group into quintiles based on lab instability
ich_quintiles AS (
    SELECT
        *,
        NTILE(5) OVER (ORDER BY distinct_abnormal_labs) AS instability_quintile
    FROM patient_level_data
    WHERE is_ich_patient = 1
),

-- Step 6: Create final report tables to be combined
quintile_results AS (
    SELECT
        'ICH Quintile Analysis' AS analysis_group,
        CAST(iq.instability_quintile AS STRING) AS group_identifier,
        COUNT(iq.hadm_id) AS number_of_patients,
        MIN(iq.distinct_abnormal_labs) AS min_distinct_abnormal_labs,
        MAX(iq.distinct_abnormal_labs) AS max_distinct_abnormal_labs,
        ROUND(AVG(iq.distinct_abnormal_labs), 2) AS avg_distinct_abnormal_labs,
        ROUND(AVG(CAST(iq.hospital_expire_flag AS INT64)) * 100, 2) AS mortality_rate_percent,
        ROUND(AVG(iq.los_days), 2) AS mean_los_days
    FROM ich_quintiles AS iq
    GROUP BY iq.instability_quintile
),

cohort_comparison AS (
    SELECT
        'Cohort Comparison' AS analysis_group,
        CASE
            WHEN is_ich_patient = 1 THEN 'ICH Patients'
            ELSE 'Control (Non-ICH) Patients'
        END AS group_identifier,
        COUNT(hadm_id) AS number_of_patients,
        NULL AS min_distinct_abnormal_labs,
        NULL AS max_distinct_abnormal_labs,
        ROUND(AVG(distinct_abnormal_labs), 2) AS avg_distinct_abnormal_labs,
        NULL AS mortality_rate_percent,
        NULL AS mean_los_days
    FROM patient_level_data
    GROUP BY is_ich_patient
)

-- Final Step: Combine the two results into a single output table
SELECT * FROM quintile_results
UNION ALL
SELECT * FROM cohort_comparison
ORDER BY analysis_group DESC, group_identifier;