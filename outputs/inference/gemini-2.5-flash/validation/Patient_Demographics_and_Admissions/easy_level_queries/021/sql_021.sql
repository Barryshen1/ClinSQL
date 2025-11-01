WITH FirstAdmissionsWithStatus AS (
    -- Identify the first admission for each patient and track its hospital_expire_flag
    SELECT
        adm.subject_id,
        adm.hadm_id,
        adm.admittime,
        adm.hospital_expire_flag,
        ROW_NUMBER() OVER (PARTITION BY adm.subject_id ORDER BY adm.admittime) as rn
    FROM
        `physionet-data.mimiciv_3_1_hosp.admissions` AS adm
),
PneumoniaFilteredAdmissions AS (
    -- Identify all unique admissions that have a pneumonia diagnosis
    SELECT DISTINCT
        diag.hadm_id
    FROM
        `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` AS diag
    WHERE
        -- Filter for pneumonia diagnosis based on ICD-10 and ICD-9 codes
        (diag.icd_version = 10 AND (
            diag.icd_code LIKE 'J12%' OR diag.icd_code LIKE 'J13%' OR diag.icd_code LIKE 'J14%' OR
            diag.icd_code LIKE 'J15%' OR diag.icd_code LIKE 'J16%' OR diag.icd_code LIKE 'J17%' OR
            diag.icd_code LIKE 'J18%'))
        OR
        (diag.icd_version = 9 AND (
            diag.icd_code LIKE '480%' OR diag.icd_code LIKE '481%' OR diag.icd_code LIKE '482%' OR
            diag.icd_code LIKE '483%' OR diag.icd_code LIKE '484%' OR diag.icd_code LIKE '485%' OR
            diag.icd_code LIKE '486%'))
),
Cohort AS (
    -- Combine the first admissions, pneumonia diagnoses, and patient demographics
    -- to define the final cohort for analysis
    SELECT
        fas.hadm_id,
        fas.hospital_expire_flag
    FROM
        FirstAdmissionsWithStatus AS fas
    INNER JOIN
        PneumoniaFilteredAdmissions AS pfa
        ON fas.hadm_id = pfa.hadm_id
    INNER JOIN
        `physionet-data.mimiciv_3_1_hosp.admissions` AS adm_details -- Re-join to get admittime for age calculation
        ON fas.hadm_id = adm_details.hadm_id
    INNER JOIN
        `physionet-data.mimiciv_3_1_hosp.patients` AS pat
        ON adm_details.subject_id = pat.subject_id
    WHERE
        fas.rn = 1 -- Ensure it's the patient's very first admission
        AND pat.gender = 'F'
        -- Calculate age at admission and filter for the specified range
        AND (pat.anchor_age + (EXTRACT(YEAR FROM adm_details.admittime) - pat.anchor_year)) BETWEEN 83 AND 93
)
-- Calculate total admissions, total deaths, and mortality percentage for the defined cohort
SELECT
    COUNT(Cohort.hadm_id) AS total_admissions_in_cohort,
    SUM(CASE WHEN Cohort.hospital_expire_flag = 1 THEN 1 ELSE 0 END) AS total_deaths_in_cohort,
    CAST(SUM(CASE WHEN Cohort.hospital_expire_flag = 1 THEN 1 ELSE 0 END) AS NUMERIC) * 100.0 / COUNT(Cohort.hadm_id) AS mortality_percentage
FROM
    Cohort;