with AMI, what is the 90th percentile of diagnostic intensity (distinct procedures in first 72 ICU hours),
-- and how do mean hospital LOS and in-hospital mortality compare to age-matched males?
-- This query identifies a cohort of male ICU patients aged 42-52 with Acute Myocardial Infarction (AMI) and compares them
-- to a broader age-matched male cohort.
-- It calculates the 90th percentile of diagnostic intensity for the AMI group and compares mean hospital LOS and mortality.

WITH
-- Step 1: Find all ICD codes related to Acute Myocardial Infarction (AMI).
ami_codes AS (
    SELECT icd_code, icd_version
    FROM `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses`
    WHERE LOWER(long_title) LIKE '%acute myocardial infarction%'
),

-- Step 2: Identify hospital admissions with an AMI diagnosis.
ami_admissions AS (
    SELECT DISTINCT dia.hadm_id
    FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` AS dia
    INNER JOIN ami_codes
        ON dia.icd_code = ami_codes.icd_code AND dia.icd_version = ami_codes.icd_version
),

-- Step 3: Define the primary cohort: Male ICU patients aged 42-52 with an AMI diagnosis.
ami_icu_cohort AS (
    SELECT
        icu.stay_id,
        icu.hadm_id,
        icu.intime
    FROM `physionet-data.mimiciv_3_1_hosp.patients` AS pat
    INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` AS adm
        ON pat.subject_id = adm.subject_id
    INNER JOIN ami_admissions
        ON adm.hadm_id = ami_admissions.hadm_id
    INNER JOIN `physionet-data.mimiciv_3_1_icu.icustays` AS icu
        ON adm.hadm_id = icu.hadm_id
    WHERE
        pat.gender = 'M'
        AND pat.anchor_age BETWEEN 42 AND 52
),

-- Step 4: Calculate diagnostic intensity (distinct procedures in first 72h) for each ICU stay in the AMI cohort.
diagnostic_intensity_per_stay AS (
    SELECT
        cohort.stay_id,
        COUNT(DISTINCT proc.itemid) AS diagnostic_intensity
    FROM ami_icu_cohort AS cohort
    LEFT JOIN `physionet-data.mimiciv_3_1_icu.procedureevents` AS proc
        ON cohort.stay_id = proc.stay_id
        -- Filter for procedures within the first 72 hours of ICU admission
        AND proc.starttime BETWEEN cohort.intime AND DATETIME_ADD(cohort.intime, INTERVAL 72 HOUR)
    GROUP BY
        cohort.stay_id
),

-- Step 5: Define the control cohort: All male hospital patients aged 42-52.
control_cohort_admissions AS (
    SELECT
        adm.hadm_id,
        adm.hospital_expire_flag,
        DATETIME_DIFF(adm.dischtime, adm.admittime, HOUR) / 24.0 AS hospital_los_days
    FROM `physionet-data.mimiciv_3_1_hosp.patients` AS pat
    INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` AS adm
        ON pat.subject_id = adm.subject_id
    WHERE
        pat.gender = 'M'
        AND pat.anchor_age BETWEEN 42 AND 52
),

-- Step 6: Calculate all summary statistics for the AMI cohort.
ami_cohort_stats AS (
    SELECT
        -- Subquery to get percentile from the per-stay intensity calculations.
        (SELECT APPROX_QUANTILES(diagnostic_intensity, 100)[OFFSET(90)] FROM diagnostic_intensity_per_stay) AS p90_diagnostic_intensity_ami,
        -- Aggregate LOS and mortality at the hospital admission level.
        AVG(DATETIME_DIFF(adm.dischtime, adm.admittime, HOUR) / 24.0) AS mean_hospital_los_ami,
        AVG(adm.hospital_expire_flag) AS in_hospital_mortality_ami
    FROM (
        SELECT DISTINCT hadm_id FROM ami_icu_cohort
    ) AS distinct_ami_hadms
    INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` AS adm
        ON distinct_ami_hadms.hadm_id = adm.hadm_id
),

-- Step 7: Calculate summary statistics for the control cohort.
control_cohort_stats AS (
    SELECT
        AVG(hospital_los_days) AS mean_hospital_los_control,
        AVG(hospital_expire_flag) AS in_hospital_mortality_control
    FROM control_cohort_admissions
)

-- Final Step: Combine and present the results.
SELECT
    ami.p90_diagnostic_intensity_ami,
    ami.mean_hospital_los_ami,
    ctrl.mean_hospital_los_control,
    ami.in_hospital_mortality_ami,
    ctrl.in_hospital_mortality_control
FROM ami_cohort_stats AS ami, control_cohort_stats AS ctrl;