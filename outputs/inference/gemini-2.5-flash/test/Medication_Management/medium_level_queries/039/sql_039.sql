WITH admissions_with_age AS (
    SELECT
        ad.subject_id,
        ad.hadm_id,
        ad.admittime,
        COALESCE(ad.deathtime, ad.dischtime) AS actual_dischtime,
        p.gender,
        p.anchor_age
    FROM
        `physionet-data.mimiciv_3_1_hosp.admissions` ad
    JOIN
        `physionet-data.mimiciv_3_1_hosp.patients` p
        ON ad.subject_id = p.subject_id
    WHERE
        p.gender = 'M'
        AND p.anchor_age BETWEEN 52 AND 62
        AND ad.admittime IS NOT NULL
        AND COALESCE(ad.deathtime, ad.dischtime) IS NOT NULL
        AND COALESCE(ad.deathtime, ad.dischtime) > ad.admittime -- Ensure valid admission duration
),
t2dm_admissions AS (
    -- Identify admissions with Type 2 Diabetes Mellitus diagnosis
    SELECT DISTINCT hadm_id
    FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` diag
    JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` dicd
        ON diag.icd_code = dicd.icd_code AND diag.icd_version = dicd.icd_version
    WHERE
        -- ICD-9: Filter for 250% codes that specifically mention 'Type 2 diabetes mellitus' in their long title
        (diag.icd_version = 9 AND diag.icd_code LIKE '250%' AND LOWER(dicd.long_title) LIKE '%type 2 diabetes mellitus%')
        -- ICD-10: Filter for E11% codes which denote Type 2 diabetes mellitus
        OR (diag.icd_version = 10 AND diag.icd_code LIKE 'E11%')
),
hf_admissions AS (
    -- Identify admissions with Heart Failure diagnosis
    SELECT DISTINCT hadm_id
    FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` diag
    WHERE
        -- ICD-9: Filter for 428% codes which denote Heart Failure
        (diag.icd_version = 9 AND diag.icd_code LIKE '428%')
        -- ICD-10: Filter for I50% codes which denote Heart Failure
        OR (diag.icd_version = 10 AND diag.icd_code LIKE 'I50%')
),
cohort_admissions AS (
    -- Combine criteria to define the final cohort of eligible admissions
    SELECT
        aws.subject_id,
        aws.hadm_id,
        aws.admittime,
        aws.actual_dischtime
    FROM
        admissions_with_age aws
    WHERE
        -- Ensure the admission has both T2DM and HF diagnoses
        EXISTS (SELECT 1 FROM t2dm_admissions t2dm WHERE aws.hadm_id = t2dm.hadm_id)
        AND EXISTS (SELECT 1 FROM hf_admissions hf WHERE aws.hadm_id = hf.hadm_id)
),
glp1_prescriptions AS (
    -- Identify injectable GLP-1 receptor agonist prescriptions
    SELECT
        p.subject_id,
        p.hadm_id,
        p.starttime,
        p.drug
    FROM
        `physionet-data.mimiciv_3_1_hosp.prescriptions` p
    WHERE
        -- Ensure the medication route is subcutaneous (injectable)
        p.route = 'SC'
        -- Filter for common GLP-1 RA drugs and their brand names
        AND (
            LOWER(p.drug) LIKE '%dulaglutide%' OR LOWER(p.drug) LIKE '%trulicity%' OR
            LOWER(p.drug) LIKE '%exenatide%' OR LOWER(p.drug) LIKE '%byetta%' OR LOWER(p.drug) LIKE '%bydureon%' OR
            LOWER(p.drug) LIKE '%liraglutide%' OR LOWER(p.drug) LIKE '%victoza%' OR LOWER(p.drug) LIKE '%saxenda%' OR
            -- Include semaglutide but exclude its oral form (Rybelsus)
            (LOWER(p.drug) LIKE '%semaglutide%' AND LOWER(p.drug) NOT LIKE '%rybelsus%') OR LOWER(p.drug) LIKE '%ozempic%' OR LOWER(p.drug) LIKE '%wegovy%'
        )
),
patient_glp1_exposure AS (
    -- Determine for each cohort admission if GLP-1 was given in the defined time windows
    SELECT
        ca.subject_id,
        ca.hadm_id,
        ca.admittime,
        ca.actual_dischtime,
        -- Calculate the start time for the "final 48 hours" window, ensuring it doesn't precede admittime
        GREATEST(ca.admittime, DATETIME_SUB(ca.actual_dischtime, INTERVAL 48 HOUR)) AS final_48h_window_start,
        -- Flag if GLP-1 was given in the first 24 hours of admission
        MAX(CASE WHEN gp.starttime BETWEEN ca.admittime AND DATETIME_ADD(ca.admittime, INTERVAL 24 HOUR) THEN 1 ELSE 0 END) AS glp1_first_24h_flag,
        -- Flag if GLP-1 was given in the final 48 hours of admission
        MAX(CASE WHEN gp.starttime BETWEEN GREATEST(ca.admittime, DATETIME_SUB(ca.actual_dischtime, INTERVAL 48 HOUR)) AND ca.actual_dischtime THEN 1 ELSE 0 END) AS glp1_final_48h_flag
    FROM
        cohort_admissions ca
    LEFT JOIN
        glp1_prescriptions gp
        ON ca.subject_id = gp.subject_id AND ca.hadm_id = gp.hadm_id
    GROUP BY
        ca.subject_id, ca.hadm_id, ca.admittime, ca.actual_dischtime
),
prevalence_calculations AS (
    -- Aggregate counts for the cohort
    SELECT
        COUNT(DISTINCT pge.subject_id || '-' || pge.hadm_id) AS total_cohort_admissions,
        SUM(pge.glp1_first_24h_flag) AS glp1_first_24h_count,
        SUM(pge.glp1_final_48h_flag) AS glp1_final_48h_count
    FROM
        patient_glp1_exposure pge
)
-- Final calculation of prevalence and change
SELECT
    total_cohort_admissions,
    glp1_first_24h_count,
    glp1_final_48h_count,

    ROUND(glp1_first_24h_count * 100.0 / total_cohort_admissions, 2) AS prevalence_first_24h_percent,
    ROUND(glp1_final_48h_count * 100.0 / total_cohort_admissions, 2) AS prevalence_final_48h_percent,

    -- Absolute change in prevalence (percentage points)
    ROUND( (glp1_final_48h_count * 100.0 / total_cohort_admissions) -
           (glp1_first_24h_count * 100.0 / total_cohort_admissions), 2) AS absolute_change_percent,

    -- Relative change in prevalence (percentage) - handles division by zero
    ROUND( CASE WHEN (glp1_first_24h_count * 100.0 / total_cohort_admissions) = 0 THEN NULL
                ELSE ( (glp1_final_48h_count * 100.0 / total_cohort_admissions) -
                       (glp1_first_24h_count * 100.0 / total_cohort_admissions) ) * 100.0 /
                     (glp1_first_24h_count * 100.0 / total_cohort_admissions)
          END, 2) AS relative_change_percent
FROM
    prevalence_calculations;