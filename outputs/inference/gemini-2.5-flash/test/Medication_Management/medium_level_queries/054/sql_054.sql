WITH DemographicsCohort AS (
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
        p.gender = 'M'
        AND p.anchor_age BETWEEN 56 AND 66 -- Age 56-66 at anchor year, assumed representative for admission.
),
DiabetesAdmissions AS (
    SELECT DISTINCT
        dc.subject_id,
        dc.hadm_id
    FROM
        DemographicsCohort AS dc
    INNER JOIN
        `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` AS di
        ON dc.subject_id = di.subject_id AND dc.hadm_id = di.hadm_id
    WHERE
        (di.icd_version = 9 AND di.icd_code LIKE '250%') -- ICD-9 diabetes codes
        OR (di.icd_version = 10 AND (
            di.icd_code LIKE 'E08%' OR di.icd_code LIKE 'E09%' OR
            di.icd_code LIKE 'E10%' OR di.icd_code LIKE 'E11%' OR
            di.icd_code LIKE 'E13%')) -- ICD-10 diabetes codes
),
HeartFailureAdmissions AS (
    SELECT DISTINCT
        dc.subject_id,
        dc.hadm_id
    FROM
        DemographicsCohort AS dc
    INNER JOIN
        `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` AS di
        ON dc.subject_id = di.subject_id AND dc.hadm_id = di.hadm_id
    WHERE
        (di.icd_version = 9 AND di.icd_code LIKE '428%') -- ICD-9 heart failure codes
        OR (di.icd_version = 10 AND di.icd_code LIKE 'I50%') -- ICD-10 heart failure codes
),
-- Final cohort of patients meeting all demographic and diagnostic criteria
FinalCohort AS (
    SELECT DISTINCT
        d_adm.subject_id,
        d_adm.hadm_id,
        dc.admittime,
        dc.dischtime
    FROM
        DiabetesAdmissions AS d_adm
    INNER JOIN
        HeartFailureAdmissions AS h_adm
        ON d_adm.subject_id = h_adm.subject_id AND d_adm.hadm_id = h_adm.hadm_id
    INNER JOIN
        DemographicsCohort AS dc
        ON d_adm.subject_id = dc.subject_id AND d_adm.hadm_id = dc.hadm_id
),
-- Base for all GLP-1 prescriptions for the FinalCohort
GLP1PrescriptionsBase AS (
    SELECT
        fc.subject_id,
        fc.hadm_id,
        p.starttime,
        fc.admittime,
        fc.dischtime
    FROM
        FinalCohort AS fc
    INNER JOIN
        `physionet-data.mimiciv_3_1_hosp.prescriptions` AS p
        ON fc.subject_id = p.subject_id AND fc.hadm_id = p.hadm_id
    WHERE
        LOWER(p.drug) LIKE '%exenatide%'
        OR LOWER(p.drug) LIKE '%liraglutide%'
        OR LOWER(p.drug) LIKE '%semaglutide%'
        OR LOWER(p.drug) LIKE '%dulaglutide%'
        OR LOWER(p.drug) LIKE '%lixisenatide%'
),
-- Admissions with GLP-1 use in the first 48 hours
GLP1_First48Hours AS (
    SELECT DISTINCT hadm_id
    FROM GLP1PrescriptionsBase
    WHERE
        starttime >= admittime
        AND starttime < DATETIME_ADD(admittime, INTERVAL 48 HOUR)
),
-- Admissions with GLP-1 use in the final 24 hours before discharge
GLP1_Final24Hours AS (
    SELECT DISTINCT hadm_id
    FROM GLP1PrescriptionsBase
    WHERE
        -- Start of the 24-hour window: later of (24 hours before discharge) or (admission_time)
        starttime >= GREATEST(DATETIME_SUB(dischtime, INTERVAL 24 HOUR), admittime)
        AND starttime < dischtime
)
-- Final calculation of prevalence and net change
SELECT
    COUNT(DISTINCT fc.hadm_id) AS total_admissions_in_cohort,
    COUNT(DISTINCT glp1_48.hadm_id) AS glp1_first_48_count,
    ROUND(COUNT(DISTINCT glp1_48.hadm_id) * 100.0 / COUNT(DISTINCT fc.hadm_id), 2) AS glp1_first_48_prevalence_pct,
    COUNT(DISTINCT glp1_24.hadm_id) AS glp1_final_24_count,
    ROUND(COUNT(DISTINCT glp1_24.hadm_id) * 100.0 / COUNT(DISTINCT fc.hadm_id), 2) AS glp1_final_24_prevalence_pct,
    ROUND((COUNT(DISTINCT glp1_24.hadm_id) - COUNT(DISTINCT glp1_48.hadm_id)) * 100.0 / COUNT(DISTINCT fc.hadm_id), 2) AS net_change_prevalence_pct
FROM
    FinalCohort AS fc
LEFT JOIN
    GLP1_First48Hours AS glp1_48
    ON fc.hadm_id = glp1_48.hadm_id
LEFT JOIN
    GLP1_Final24Hours AS glp1_24
    ON fc.hadm_id = glp1_24.hadm_id;