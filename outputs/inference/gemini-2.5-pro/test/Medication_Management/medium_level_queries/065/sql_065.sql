WITH
-- Step 1: Define the patient cohort.
-- This CTE finds hospital admissions for male patients aged 77-87 with both diabetes and heart failure.
cohort_diagnoses AS (
    SELECT
        hadm_id,
        MAX(CASE WHEN LOWER(d.long_title) LIKE '%diabetes mellitus%' THEN 1 ELSE 0 END) AS has_diabetes,
        MAX(CASE WHEN LOWER(d.long_title) LIKE '%heart failure%' THEN 1 ELSE 0 END) AS has_heart_failure
    FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` AS dx
    INNER JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` AS d
        ON dx.icd_code = d.icd_code AND dx.icd_version = d.icd_version
    GROUP BY hadm_id
    HAVING has_diabetes = 1 AND has_heart_failure = 1
),

cohort AS (
    SELECT
        a.hadm_id,
        a.admittime,
        a.dischtime
    FROM `physionet-data.mimiciv_3_1_hosp.admissions` AS a
    INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` AS p
        ON a.subject_id = p.subject_id
    INNER JOIN cohort_diagnoses AS cd
        ON a.hadm_id = cd.hadm_id
    WHERE
        p.gender = 'M'
        AND p.anchor_age BETWEEN 77 AND 87
),

-- Step 2: Identify medication initiations for insulin vs. oral agents for the cohort.
med_initiations AS (
    SELECT
        pr.hadm_id,
        CASE
            WHEN LOWER(pr.drug) LIKE '%insulin%' THEN 'Insulin'
            WHEN pr.route = 'PO' AND (
                LOWER(pr.drug) LIKE '%metformin%' OR
                LOWER(pr.drug) LIKE '%glipizide%' OR
                LOWER(pr.drug) LIKE '%glyburide%' OR
                LOWER(pr.drug) LIKE '%glimepiride%' OR
                LOWER(pr.drug) LIKE '%pioglitazone%' OR
                LOWER(pr.drug) LIKE '%rosiglitazone%' OR
                LOWER(pr.drug) LIKE '%sitagliptin%' OR
                LOWER(pr.drug) LIKE '%saxagliptin%' OR
                LOWER(pr.drug) LIKE '%linagliptin%' OR
                LOWER(pr.drug) LIKE '%alogliptin%' OR
                LOWER(pr.drug) LIKE '%canagliflozin%' OR
                LOWER(pr.drug) LIKE '%dapagliflozin%' OR
                LOWER(pr.drug) LIKE '%empagliflozin%' OR
                LOWER(pr.drug) LIKE '%repaglinide%' OR
                LOWER(pr.drug) LIKE '%nateglinide%' OR
                LOWER(pr.drug) LIKE '%acarbose%' OR
                LOWER(pr.drug) LIKE '%miglitol%'
            ) THEN 'Oral Agent'
        END AS drug_class,
        -- Get the first administration time for each drug class per admission.
        MIN(pr.starttime) AS initiation_time
    FROM `physionet-data.mimiciv_3_1_hosp.prescriptions` AS pr
    -- Pre-filter prescriptions to only our cohort for efficiency.
    WHERE pr.hadm_id IN (SELECT hadm_id FROM cohort) AND pr.starttime IS NOT NULL
    GROUP BY pr.hadm_id, drug_class
    HAVING drug_class IS NOT NULL
),

-- Step 3: For each patient and drug class, flag if initiation occurred in the specified windows.
patient_flags AS (
    SELECT
        c.hadm_id,
        mi.drug_class,
        -- Flag if the first prescription was within the first 48 hours of admission.
        MAX(CASE
            WHEN mi.initiation_time BETWEEN c.admittime AND DATETIME_ADD(c.admittime, INTERVAL 48 HOUR)
            THEN 1 ELSE 0
        END) AS initiated_first_48h,
        -- Flag if the first prescription was within the final 72 hours of admission.
        MAX(CASE
            WHEN mi.initiation_time BETWEEN DATETIME_SUB(c.dischtime, INTERVAL 72 HOUR) AND c.dischtime
            THEN 1 ELSE 0
        END) AS initiated_final_72h
    FROM cohort AS c
    LEFT JOIN med_initiations AS mi
        ON c.hadm_id = mi.hadm_id
    GROUP BY c.hadm_id, mi.drug_class
),

-- Step 4: Count the number of patients initiated in each window for each drug class.
final_counts AS (
    SELECT
        drug_class,
        COUNT(DISTINCT CASE WHEN initiated_first_48h = 1 THEN hadm_id END) AS count_first_48h,
        COUNT(DISTINCT CASE WHEN initiated_final_72h = 1 THEN hadm_id END) AS count_final_72h
    FROM patient_flags
    WHERE drug_class IS NOT NULL
    GROUP BY drug_class
)

-- Final Step: Calculate the rates and the net change in percentage points (pp).
SELECT
    fc.drug_class,
    -- Initiation Rate 0-48h (%)
    SAFE_DIVIDE(fc.count_first_48h, total_patients.count) * 100 AS initiation_rate_0_48h_pct,
    -- Initiation Rate final 72h (%)
    SAFE_DIVIDE(fc.count_final_72h, total_patients.count) * 100 AS initiation_rate_final_72h_pct,
    -- Net Change (pp) = (Final Rate) - (Initial Rate)
    (SAFE_DIVIDE(fc.count_final_72h, total_patients.count) * 100) - (SAFE_DIVIDE(fc.count_first_48h, total_patients.count) * 100) AS net_change_pp
FROM final_counts AS fc,
-- Subquery to get the total number of patients in the cohort for the denominator.
(SELECT COUNT(hadm_id) AS count FROM cohort) AS total_patients
ORDER BY fc.drug_class;