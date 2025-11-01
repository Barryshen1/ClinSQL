WITH cohort_admissions AS (
    -- Step 1: Identify the main cohort based on gender, age, and admission duration
    SELECT
        ad.subject_id,
        ad.hadm_id,
        ad.admittime,
        ad.dischtime,
        TIMESTAMP_DIFF(ad.dischtime, ad.admittime, HOUR) AS admission_duration_hours
    FROM
        `physionet-data.mimiciv_3_1_hosp`.admissions ad
    INNER JOIN
        `physionet-data.mimiciv_3_1_hosp`.patients p
        ON ad.subject_id = p.subject_id
    WHERE
        p.gender = 'F'
        AND p.anchor_age BETWEEN 37 AND 47 -- Age at anchor_year, used as a proxy for age at admission
        AND TIMESTAMP_DIFF(ad.dischtime, ad.admittime, HOUR) >= 144
),
cohort_diagnoses AS (
    -- Step 2: Filter the cohort for patients with both Diabetes and Heart Failure diagnoses
    SELECT
        ca.subject_id,
        ca.hadm_id,
        ca.admittime,
        ca.dischtime,
        ca.admission_duration_hours
    FROM
        cohort_admissions ca
    WHERE
        -- Check for Diabetes diagnosis (ICD-9: 250.xx, ICD-10: E08-E13)
        EXISTS (
            SELECT 1
            FROM `physionet-data.mimiciv_3_1_hosp`.diagnoses_icd di
            WHERE di.subject_id = ca.subject_id AND di.hadm_id = ca.hadm_id
            AND
            (
                (di.icd_version = 9 AND di.icd_code LIKE '250%')
                OR
                (di.icd_version = 10 AND di.icd_code BETWEEN 'E08' AND 'E139') -- Covers E08.x to E13.x
            )
        )
        -- Check for Heart Failure diagnosis (ICD-9: 428.xx, ICD-10: I50.xx)
        AND EXISTS (
            SELECT 1
            FROM `physionet-data.mimiciv_3_1_hosp`.diagnoses_icd di
            WHERE di.subject_id = ca.subject_id AND di.hadm_id = ca.hadm_id
            AND
            (
                (di.icd_version = 9 AND di.icd_code LIKE '428%')
                OR
                (di.icd_version = 10 AND di.icd_code LIKE 'I50%')
            )
        )
),
prescriptions_classified AS (
    -- Step 3: Classify prescriptions into target drug categories
    SELECT
        p.hadm_id,
        p.starttime,
        LOWER(p.drug) AS drug_name_lower,
        CASE
            WHEN LOWER(p.drug) LIKE '%insulin%'
                 OR LOWER(p.drug) LIKE '%metformin%'
                 OR LOWER(p.drug) LIKE '%glipizide%'
                 OR LOWER(p.drug) LIKE '%glyburide%'
                 OR LOWER(p.drug) LIKE '%glimepiride%'
                 OR LOWER(p.drug) LIKE '%sitagliptin%'
                 OR LOWER(p.drug) LIKE '%saxagliptin%'
                 OR LOWER(p.drug) LIKE '%linagliptin%'
                 OR LOWER(p.drug) LIKE '%canagliflozin%'
                 OR LOWER(p.drug) LIKE '%dapagliflozin%'
                 OR LOWER(p.drug) LIKE '%empagliflozin%'
                 OR LOWER(p.drug) LIKE '%exenatide%'
                 OR LOWER(p.drug) LIKE '%liraglutide%'
                 OR LOWER(p.drug) LIKE '%semaglutide%'
                 THEN 'Antidiabetics'
            WHEN LOWER(p.drug) LIKE '%atenolol%'
                 OR LOWER(p.drug) LIKE '%carvedilol%'
                 OR LOWER(p.drug) LIKE '%labetalol%'
                 OR LOWER(p.drug) LIKE '%metoprolol%'
                 OR LOWER(p.drug) LIKE '%propranolol%'
                 OR LOWER(p.drug) LIKE '%bisoprolol%'
                 OR LOWER(p.drug) LIKE '%sotalol%'
                 THEN 'Beta-blockers'
            WHEN LOWER(p.drug) LIKE '%lisinopril%'
                 OR LOWER(p.drug) LIKE '%enalapril%'
                 OR LOWER(p.drug) LIKE '%ramipril%'
                 OR LOWER(p.drug) LIKE '%captopril%'
                 OR LOWER(p.drug) LIKE '%losartan%'
                 OR LOWER(p.drug) LIKE '%valsartan%'
                 OR LOWER(p.drug) LIKE '%candesartan%'
                 OR LOWER(p.drug) LIKE '%irbesartan%'
                 OR LOWER(p.drug) LIKE '%telmisartan%'
                 OR LOWER(p.drug) LIKE '%sacubitril%' -- for ARNI (Sacubitril/Valsartan)
                 THEN 'ACEi/ARB/ARNI'
            WHEN LOWER(p.drug) LIKE '%furosemide%'
                 OR LOWER(p.drug) LIKE '%bumetanide%'
                 OR LOWER(p.drug) LIKE '%torsemide%'
                 THEN 'Loop Diuretics'
            ELSE NULL
        END AS drug_category
    FROM
        `physionet-data.mimiciv_3_1_hosp`.prescriptions p
    WHERE
        p.drug IS NOT NULL -- Exclude prescriptions without a drug name
),
patient_drug_windows AS (
    -- Step 4: Determine drug presence in first and final 72-hour windows for each patient
    SELECT
        cd.hadm_id,
        pc.drug_category,
        MAX(CASE WHEN pc.starttime >= cd.admittime AND pc.starttime <= TIMESTAMP_ADD(cd.admittime, INTERVAL 72 HOUR) THEN 1 ELSE 0 END) AS in_first_72h,
        MAX(CASE WHEN pc.starttime >= TIMESTAMP_SUB(cd.dischtime, INTERVAL 72 HOUR) AND pc.starttime <= cd.dischtime THEN 1 ELSE 0 END) AS in_final_72h
    FROM
        cohort_diagnoses cd
    JOIN
        prescriptions_classified pc
        ON cd.hadm_id = pc.hadm_id
    WHERE
        pc.drug_category IS NOT NULL
        AND pc.starttime BETWEEN cd.admittime AND cd.dischtime -- Ensure prescription is within admission
    GROUP BY
        cd.hadm_id,
        pc.drug_category
),
final_analysis AS (
    -- Step 5: Aggregate results for percentages and transition counts
    SELECT
        drug_category,
        SUM(in_first_72h) AS patients_on_first_72h,
        SUM(in_final_72h) AS patients_on_final_72h,
        -- Transition counts
        SUM(CASE WHEN in_first_72h = 0 AND in_final_72h = 1 THEN 1 ELSE 0 END) AS initiated_count,
        SUM(CASE WHEN in_first_72h = 1 AND in_final_72h = 1 THEN 1 ELSE 0 END) AS continued_count,
        SUM(CASE WHEN in_first_72h = 1 AND in_final_72h = 0 THEN 1 ELSE 0 END) AS discontinued_count
    FROM
        patient_drug_windows
    GROUP BY
        drug_category
),
cohort_size AS (
    -- Calculate the total number of unique patients in the defined cohort
    SELECT COUNT(DISTINCT hadm_id) AS total_cohort_patients
    FROM cohort_diagnoses
)
-- Final result selection
SELECT
    fa.drug_category,
    (fa.patients_on_first_72h * 100.0 / cs.total_cohort_patients) AS percent_on_first_72h,
    (fa.patients_on_final_72h * 100.0 / cs.total_cohort_patients) AS percent_on_final_72h,
    fa.initiated_count,
    fa.continued_count,
    fa.discontinued_count
FROM
    final_analysis fa,
    cohort_size cs -- Join with cohort_size to get the total patient count for percentage calculation
ORDER BY
    fa.drug_category;