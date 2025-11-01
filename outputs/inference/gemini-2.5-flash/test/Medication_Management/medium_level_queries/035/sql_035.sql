WITH AdmissionsCohort AS (
    -- Step 1: Identify the initial cohort of female inpatients, 57-67 years old.
    -- We ensure dischtime is not NULL and admission length is at least 12 hours
    -- to allow for the final 12h pre-discharge window.
    SELECT
        ad.subject_id,
        ad.hadm_id,
        ad.admittime,
        ad.dischtime
    FROM
        `physionet-data.mimiciv_3_1_hosp.admissions` AS ad
    INNER JOIN
        `physionet-data.mimiciv_3_1_hosp.patients` AS p
        ON ad.subject_id = p.subject_id
    WHERE
        p.gender = 'F'
        AND p.anchor_age BETWEEN 57 AND 67
        AND ad.dischtime IS NOT NULL -- Exclude ongoing admissions for discharge-related analysis
        AND DATETIME_DIFF(ad.dischtime, ad.admittime, HOUR) >= 12 -- Ensure at least a 12-hour stay for pre-discharge window
),
DiabetesAdmissions AS (
    -- Identify admissions with a diagnosis of Diabetes (ICD-10 E10-E13, ICD-9 250)
    SELECT DISTINCT hadm_id
    FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd`
    WHERE
        (icd_version = 10 AND (icd_code LIKE 'E10.%' OR icd_code LIKE 'E11.%' OR icd_code LIKE 'E13.%'))
        OR (icd_version = 9 AND icd_code LIKE '250.%')
),
HeartFailureAdmissions AS (
    -- Identify admissions with a diagnosis of Heart Failure (ICD-10 I50, ICD-9 428)
    SELECT DISTINCT hadm_id
    FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd`
    WHERE
        (icd_version = 10 AND icd_code LIKE 'I50.%')
        OR (icd_version = 9 AND icd_code LIKE '428.%')
),
FinalCohort AS (
    -- Combine the demographic cohort with diabetes and heart failure diagnoses
    SELECT ac.subject_id, ac.hadm_id, ac.admittime, ac.dischtime
    FROM AdmissionsCohort ac
    INNER JOIN DiabetesAdmissions da ON ac.hadm_id = da.hadm_id
    INNER JOIN HeartFailureAdmissions hfa ON ac.hadm_id = hfa.hadm_id
),
GLP1_RA_Prescriptions AS (
    -- Identify prescriptions for GLP-1 Receptor Agonists
    SELECT
        p.hadm_id,
        p.starttime
    FROM
        `physionet-data.mimiciv_3_1_hosp.prescriptions` AS p
    WHERE
        LOWER(p.drug) LIKE '%semaglutide%' OR
        LOWER(p.drug) LIKE '%liraglutide%' OR
        LOWER(p.drug) LIKE '%exenatide%' OR
        LOWER(p.drug) LIKE '%dulaglutide%' OR
        LOWER(p.drug) LIKE '%lixisenatide%' OR
        LOWER(p.drug) LIKE '%albiglutide%'
),
PatientGLP1_RA_Status AS (
    -- For each admission in the final cohort, determine if a GLP-1 RA was prescribed
    -- in the first 48 hours and in the final 12 hours before discharge.
    SELECT
        fc.hadm_id,
        -- Flag for prescription in the first 48 hours of admission
        MAX(CASE
            WHEN glp.starttime BETWEEN fc.admittime AND DATETIME_ADD(fc.admittime, INTERVAL 48 HOUR)
            THEN 1
            ELSE 0
        END) AS has_glp1_ra_first_48h,
        -- Flag for prescription in the final 12 hours before discharge
        MAX(CASE
            WHEN glp.starttime BETWEEN DATETIME_SUB(fc.dischtime, INTERVAL 12 HOUR) AND DATETIME_ADD(fc.dischtime, INTERVAL 1 MINUTE) -- Add 1 minute to make it inclusive of dischtime
            THEN 1
            ELSE 0
        END) AS has_glp1_ra_final_12h
    FROM
        FinalCohort fc
    LEFT JOIN
        GLP1_RA_Prescriptions glp
        ON fc.hadm_id = glp.hadm_id
    GROUP BY
        fc.hadm_id
),
PrevalenceCalculation AS (
    -- Calculate the total number of admissions in the cohort and the counts
    -- of admissions with GLP-1 RA prescriptions in each time window.
    SELECT
        COUNT(DISTINCT hadm_id) AS total_admissions_in_cohort,
        SUM(has_glp1_ra_first_48h) AS count_glp1_ra_first_48h,
        SUM(has_glp1_ra_final_12h) AS count_glp1_ra_final_12h,
        -- Calculate prevalence as a proportion
        SAFE_DIVIDE(SUM(has_glp1_ra_first_48h), COUNT(DISTINCT hadm_id)) AS prevalence_first_48h_ratio,
        SAFE_DIVIDE(SUM(has_glp1_ra_final_12h), COUNT(DISTINCT hadm_id)) AS prevalence_final_12h_ratio
    FROM
        PatientGLP1_RA_Status
)
-- Final selection: calculate percentages, absolute, and relative changes.
SELECT
    total_admissions_in_cohort,
    CAST(prevalence_first_48h_ratio * 100 AS BIGNUMERIC) AS prevalence_first_48h_percent,
    CAST(prevalence_final_12h_ratio * 100 AS BIGNUMERIC) AS prevalence_final_12h_percent,
    CAST((prevalence_final_12h_ratio - prevalence_first_48h_ratio) * 100 AS BIGNUMERIC) AS absolute_change_percent_points,
    -- Relative change is (New - Old) / Old * 100
    CAST(SAFE_DIVIDE((prevalence_final_12h_ratio - prevalence_first_48h_ratio), prevalence_first_48h_ratio) * 100 AS BIGNUMERIC) AS relative_change_percent
FROM
    PrevalenceCalculation;