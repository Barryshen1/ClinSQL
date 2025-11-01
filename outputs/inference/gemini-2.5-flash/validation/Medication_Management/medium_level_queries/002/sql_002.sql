WITH admissions_filtered AS (
    -- Step 1: Filter admissions for female patients aged 59-69 with stay >= 48 hours
    SELECT
        adm.subject_id,
        adm.hadm_id,
        adm.admittime,
        adm.dischtime
    FROM
        `physionet-data.mimiciv_3_1_hosp.admissions` adm
    INNER JOIN
        `physionet-data.mimiciv_3_1_hosp.patients` pat
        ON adm.subject_id = pat.subject_id
    WHERE
        pat.gender = 'F'
        AND pat.anchor_age BETWEEN 59 AND 69
        AND TIMESTAMP_DIFF(adm.dischtime, adm.admittime, HOUR) >= 48
),
patient_diagnoses AS (
    -- Step 2: Identify admissions with both T2DM (E11.x) and Heart Failure (I50.x) (ICD-10)
    SELECT
        hadm_id,
        MAX(CASE WHEN dg.icd_version = 10 AND LEFT(dg.icd_code, 3) = 'E11' THEN 1 ELSE 0 END) AS has_t2dm,
        MAX(CASE WHEN dg.icd_version = 10 AND LEFT(dg.icd_code, 3) = 'I50' THEN 1 ELSE 0 END) AS has_hf
    FROM
        `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` dg
    WHERE
        dg.icd_version = 10
    GROUP BY
        hadm_id
),
eligible_cohort AS (
    -- Step 3: Combine filtered admissions with diagnosis requirements
    SELECT
        af.subject_id,
        af.hadm_id,
        af.admittime,
        af.dischtime
    FROM
        admissions_filtered af
    INNER JOIN
        patient_diagnoses pd
        ON af.hadm_id = pd.hadm_id
    WHERE
        pd.has_t2dm = 1 AND pd.has_hf = 1
),
glp1_receipt AS (
    -- Step 4: Identify injectable GLP-1 RA prescriptions within each time window
    SELECT DISTINCT -- Use DISTINCT to count each hadm_id only once per time window
        ec.hadm_id,
        -- Check for GLP-1 RA receipt in the first 48 hours
        CASE
            WHEN p.starttime >= ec.admittime
            AND p.starttime < TIMESTAMP_ADD(ec.admittime, INTERVAL 48 HOUR)
            THEN 1
            ELSE 0
        END AS received_glp1_first_48h,
        -- Check for GLP-1 RA receipt in the final 12 hours
        CASE
            WHEN p.starttime >= TIMESTAMP_SUB(ec.dischtime, INTERVAL 12 HOUR)
            AND p.starttime < ec.dischtime
            THEN 1
            ELSE 0
        END AS received_glp1_final_12h
    FROM
        eligible_cohort ec
    INNER JOIN
        `physionet-data.mimiciv_3_1_hosp.prescriptions` p
        ON ec.subject_id = p.subject_id AND ec.hadm_id = p.hadm_id
    WHERE
        -- Filter for common injectable GLP-1 RAs/GIP-GLP1 RAs
           (LOWER(p.drug) LIKE '%semaglutide%'
        OR LOWER(p.drug) LIKE '%liraglutide%'
        OR LOWER(p.drug) LIKE '%dulaglutide%'
        OR LOWER(p.drug) LIKE '%exenatide%'
        OR LOWER(p.drug) LIKE '%lixisenatide%'
        OR LOWER(p.drug) LIKE '%tirzepatide%')
        -- Ensure the route is injectable
        AND LOWER(p.route) IN ('sc', 'subq', 'inj', 'iv', 'intravenous')
)
-- Step 5: Calculate total eligible admissions, counts, prevalences, and the absolute difference
SELECT
    COUNT(DISTINCT ec.hadm_id) AS total_eligible_admissions,
    COALESCE(COUNT(DISTINCT CASE WHEN gr.received_glp1_first_48h = 1 THEN gr.hadm_id END), 0) AS admissions_with_glp1_first_48h,
    COALESCE(COUNT(DISTINCT CASE WHEN gr.received_glp1_final_12h = 1 THEN gr.hadm_id END), 0) AS admissions_with_glp1_final_12h,
    (COALESCE(COUNT(DISTINCT CASE WHEN gr.received_glp1_first_48h = 1 THEN gr.hadm_id END), 0) * 100.0 / COUNT(DISTINCT ec.hadm_id)) AS prevalence_first_48h_percent,
    (COALESCE(COUNT(DISTINCT CASE WHEN gr.received_glp1_final_12h = 1 THEN gr.hadm_id END), 0) * 100.0 / COUNT(DISTINCT ec.hadm_id)) AS prevalence_final_12h_percent,
    (
        (COALESCE(COUNT(DISTINCT CASE WHEN gr.received_glp1_first_48h = 1 THEN gr.hadm_id END), 0) * 100.0 / COUNT(DISTINCT ec.hadm_id))
        -
        (COALESCE(COUNT(DISTINCT CASE WHEN gr.received_glp1_final_12h = 1 THEN gr.hadm_id END), 0) * 100.0 / COUNT(DISTINCT ec.hadm_id))
    ) AS absolute_pp_difference
FROM
    eligible_cohort ec
LEFT JOIN
    glp1_receipt gr
    ON ec.hadm_id = gr.hadm_id;