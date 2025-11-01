WITH AdmissionsFiltered AS (
    SELECT
        ad.subject_id,
        ad.hadm_id,
        ad.admittime,
        ad.dischtime,
        -- Calculate approximate age at admission using anchor_age and anchor_year
        (pa.anchor_age + (EXTRACT(YEAR FROM ad.admittime) - pa.anchor_year)) AS age_at_admission,
        DATETIME_DIFF(ad.dischtime, ad.admittime, HOUR) AS admission_duration_hours
    FROM
        `physionet-data.mimiciv_3_1_hosp`.admissions AS ad
    INNER JOIN
        `physionet-data.mimiciv_3_1_hosp`.patients AS pa
        ON ad.subject_id = pa.subject_id
    WHERE
        pa.gender = 'F'
        -- Apply age and duration filters earlier to reduce dataset size
        AND (pa.anchor_age + (EXTRACT(YEAR FROM ad.admittime) - pa.anchor_year)) BETWEEN 50 AND 60
        AND DATETIME_DIFF(ad.dischtime, ad.admittime, HOUR) >= 72
),
CohortDiagnoses AS (
    SELECT
        af.subject_id,
        af.hadm_id,
        af.admittime,
        af.dischtime,
        af.admission_duration_hours,
        -- Flag for Type 2 Diabetes
        MAX(CASE
            WHEN (di.icd_version = 10 AND di.icd_code LIKE 'E11%')
                 OR (di.icd_version = 9 AND di.icd_code LIKE '250%')
            THEN 1 ELSE 0 END) AS has_diabetes_t2,
        -- Flag for Heart Failure
        MAX(CASE
            WHEN (di.icd_version = 10 AND di.icd_code LIKE 'I50%')
                 OR (di.icd_version = 9 AND di.icd_code LIKE '428%')
            THEN 1 ELSE 0 END) AS has_heart_failure
    FROM
        AdmissionsFiltered AS af
    INNER JOIN
        `physionet-data.mimiciv_3_1_hosp`.diagnoses_icd AS di
        ON af.subject_id = di.subject_id AND af.hadm_id = di.hadm_id
    GROUP BY
        af.subject_id, af.hadm_id, af.admittime, af.dischtime, af.admission_duration_hours
),
FinalCohort AS (
    SELECT
        subject_id,
        hadm_id,
        admittime,
        dischtime,
        admission_duration_hours
    FROM
        CohortDiagnoses
    WHERE
        has_diabetes_t2 = 1
        AND has_heart_failure = 1
),
GLP_1_Meds AS (
    SELECT
        DISTINCT ps.subject_id,
        ps.hadm_id,
        ps.starttime
    FROM
        `physionet-data.mimiciv_3_1_hosp`.prescriptions AS ps
    WHERE
        LOWER(ps.drug) LIKE '%semaglutide%'
        OR LOWER(ps.drug) LIKE '%liraglutide%'
        OR LOWER(ps.drug) LIKE '%dulaglutide%'
        OR LOWER(ps.drug) LIKE '%exenatide%'
        OR LOWER(ps.drug) LIKE '%lixisenatide%'
        OR LOWER(ps.drug) LIKE '%tirzepatide%' -- Including GIP/GLP-1 co-agonist
),
PatientGLP1Status AS (
    -- Calculate GLP-1 initiation and prevalence flags for each patient in the cohort
    SELECT
        fc.subject_id,
        fc.hadm_id,
        fc.admittime,
        -- Flag for GLP-1 initiation within the first 12 hours of admission
        MAX(CASE
            WHEN gm.starttime IS NOT NULL
                 AND gm.starttime BETWEEN fc.admittime AND DATETIME_ADD(fc.admittime, INTERVAL 12 HOUR)
            THEN 1 ELSE 0 END) AS glp1_initiation_12hr_flag,
        -- Flag for GLP-1 prevalence within the first 72 hours of admission
        MAX(CASE
            WHEN gm.starttime IS NOT NULL
                 AND gm.starttime BETWEEN fc.admittime AND DATETIME_ADD(fc.admittime, INTERVAL 72 HOUR)
            THEN 1 ELSE 0 END) AS glp1_prevalence_72hr_flag
    FROM
        FinalCohort AS fc
    LEFT JOIN
        GLP_1_Meds AS gm
        ON fc.subject_id = gm.subject_id AND fc.hadm_id = gm.hadm_id
    GROUP BY
        fc.subject_id, fc.hadm_id, fc.admittime
)
-- Final aggregation to calculate total cohort metrics and percentages
SELECT
    COUNT(DISTINCT pgs.hadm_id) AS total_cohort_admissions,

    SUM(pgs.glp1_initiation_12hr_flag) AS glp1_initiation_12hr_count,
    -- Calculate GLP-1 initiation within the first 12 hours as a percentage
    CAST(SUM(pgs.glp1_initiation_12hr_flag) AS FLOAT64) * 100 / COUNT(DISTINCT pgs.hadm_id) AS glp1_initiation_12hr_percentage,

    SUM(pgs.glp1_prevalence_72hr_flag) AS glp1_prevalence_72hr_count,
    -- Calculate GLP-1 prevalence within the first 72 hours as a percentage
    CAST(SUM(pgs.glp1_prevalence_72hr_flag) AS FLOAT64) * 100 / COUNT(DISTINCT pgs.hadm_id) AS glp1_prevalence_72hr_percentage,

    -- Calculate the net percentage-point change
    (CAST(SUM(pgs.glp1_prevalence_72hr_flag) AS FLOAT64) * 100 / COUNT(DISTINCT pgs.hadm_id)) -
    (CAST(SUM(pgs.glp1_initiation_12hr_flag) AS FLOAT64) * 100 / COUNT(DISTINCT pgs.hadm_id)) AS net_percentage_point_change
FROM
    PatientGLP1Status AS pgs;