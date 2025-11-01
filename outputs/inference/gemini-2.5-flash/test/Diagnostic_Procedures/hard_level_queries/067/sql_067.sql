WITH hf_patients_icustays AS (
    SELECT DISTINCT
        ie.subject_id,
        ie.hadm_id,
        ie.stay_id,
        ie.intime,
        ie.outtime,
        ie.los,
        adm.hospital_expire_flag
    FROM
        `physionet-data.mimiciv_3_1_icu.icustays` ie
    INNER JOIN
        `physionet-data.mimiciv_3_1_hosp.admissions` adm
        ON ie.subject_id = adm.subject_id AND ie.hadm_id = adm.hadm_id
    INNER JOIN
        `physionet-data.mimiciv_3_1_hosp.patients` p
        ON ie.subject_id = p.subject_id
    INNER JOIN
        `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` di
        ON ie.subject_id = di.subject_id AND ie.hadm_id = di.hadm_id
    WHERE
        p.gender = 'M'
        AND p.anchor_age BETWEEN 70 AND 80
        AND (
            (di.icd_version = 9 AND di.icd_code LIKE '428%') -- ICD-9 codes for Heart Failure
            OR (di.icd_version = 10 AND di.icd_code LIKE 'I50%') -- ICD-10 codes for Heart Failure
        )
),
-- CTE to calculate distinct lab items (diagnostic intensity) in the first 72 hours for ALL ICU stays.
-- This is pre-calculated to be reused for both cohorts.
all_icu_lab_intensity AS (
    SELECT
        ie.subject_id,
        ie.hadm_id,
        ie.stay_id,
        COUNT(DISTINCT le.itemid) AS diagnostic_intensity_72h
    FROM
        `physionet-data.mimiciv_3_1_icu.icustays` ie
    INNER JOIN
        `physionet-data.mimiciv_3_1_hosp.labevents` le
        ON ie.subject_id = le.subject_id
        AND ie.hadm_id = le.hadm_id
    WHERE
        le.charttime BETWEEN ie.intime AND DATETIME_ADD(ie.intime, INTERVAL 72 HOUR)
    GROUP BY
        ie.subject_id, ie.hadm_id, ie.stay_id
),
-- CTE to assemble the data for the Heart Failure Cohort, joining with lab intensity
hf_cohort_data AS (
    SELECT
        hic.subject_id,
        hic.hadm_id,
        hic.stay_id,
        hic.los,
        hic.hospital_expire_flag,
        -- COALESCE handles cases where an ICU stay might have no lab events in the first 72 hours
        COALESCE(ali.diagnostic_intensity_72h, 0) AS diagnostic_intensity_72h
    FROM
        hf_patients_icustays hic
    LEFT JOIN
        all_icu_lab_intensity ali
        ON hic.subject_id = ali.subject_id
        AND hic.hadm_id = ali.hadm_id
        AND hic.stay_id = ali.stay_id
),
-- CTE to assemble the data for the General ICU Population, joining with lab intensity
general_icu_data AS (
    SELECT
        ie.subject_id,
        ie.hadm_id,
        ie.stay_id,
        ie.los,
        adm.hospital_expire_flag,
        -- COALESCE handles cases where an ICU stay might have no lab events in the first 72 hours
        COALESCE(ali.diagnostic_intensity_72h, 0) AS diagnostic_intensity_72h
    FROM
        `physionet-data.mimiciv_3_1_icu.icustays` ie
    INNER JOIN
        `physionet-data.mimiciv_3_1_hosp.admissions` adm
        ON ie.subject_id = adm.subject_id AND ie.hadm_id = adm.hadm_id
    LEFT JOIN
        all_icu_lab_intensity ali
        ON ie.subject_id = ali.subject_id
        AND ie.hadm_id = ali.hadm_id
        AND ie.stay_id = ali.stay_id
)
-- Final aggregation to calculate and present results for the Heart Failure Cohort
SELECT
    'Heart Failure Cohort (Male, 70-80 years)' AS cohort,
    COUNT(DISTINCT stay_id) AS number_of_icu_stays,
    ROUND(AVG(diagnostic_intensity_72h), 2) AS mean_diag_intensity_72h,
    ROUND(APPROX_QUANTILES(diagnostic_intensity_72h, 100)[OFFSET(50)], 2) AS median_diag_intensity_72h,
    ROUND(APPROX_QUANTILES(diagnostic_intensity_72h, 100)[OFFSET(75)], 2) AS p75_diag_intensity_72h,
    ROUND(APPROX_QUANTILES(diagnostic_intensity_72h, 100)[OFFSET(95)], 2) AS p95_diag_intensity_72h,
    ROUND(AVG(los), 2) AS mean_icu_los_days,
    ROUND((SUM(hospital_expire_flag) * 100.0 / COUNT(*)), 2) AS hospital_mortality_percent
FROM
    hf_cohort_data

UNION ALL

-- Final aggregation to calculate and present results for the General ICU Population
SELECT
    'General ICU Population' AS cohort,
    COUNT(DISTINCT stay_id) AS number_of_icu_stays,
    ROUND(AVG(diagnostic_intensity_72h), 2) AS mean_diag_intensity_72h,
    ROUND(APPROX_QUANTILES(diagnostic_intensity_72h, 100)[OFFSET(50)], 2) AS median_diag_intensity_72h,
    ROUND(APPROX_QUANTILES(diagnostic_intensity_72h, 100)[OFFSET(75)], 2) AS p75_diag_intensity_72h,
    ROUND(APPROX_QUANTILES(diagnostic_intensity_72h, 100)[OFFSET(95)], 2) AS p95_diag_intensity_72h,
    ROUND(AVG(los), 2) AS mean_icu_los_days,
    ROUND((SUM(hospital_expire_flag) * 100.0 / COUNT(*)), 2) AS hospital_mortality_percent
FROM
    general_icu_data;