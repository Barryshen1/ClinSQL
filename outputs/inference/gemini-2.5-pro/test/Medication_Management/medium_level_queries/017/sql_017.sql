WITH
-- Step 1: Find all hospital admissions for female patients aged 37-47
-- with a length of stay >= 144 hours.
cohort_base AS (
    SELECT
        p.subject_id,
        a.hadm_id,
        a.admittime,
        a.dischtime
    FROM
        `physionet-data.mimiciv_3_1_hosp.patients` AS p
    INNER JOIN
        `physionet-data.mimiciv_3_1_hosp.admissions` AS a
            ON p.subject_id = a.subject_id
    WHERE
        p.gender = 'F'
        AND (EXTRACT(YEAR FROM a.admittime) - p.anchor_year) + p.anchor_age BETWEEN 37 AND 47
        AND DATETIME_DIFF(a.dischtime, a.admittime, HOUR) >= 144
),

-- Step 2: Identify admissions from the base cohort that have diagnoses for
-- both Diabetes and Heart Failure.
hadm_with_diagnoses AS (
    SELECT hadm_id FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd`
    WHERE
        -- Filter for Diabetes ICD codes (ICD-9: 250.xx; ICD-10: E08-E13)
        (icd_version = 9 AND icd_code LIKE '250%')
        OR (icd_version = 10 AND (icd_code LIKE 'E08%' OR icd_code LIKE 'E09%' OR icd_code LIKE 'E10%' OR icd_code LIKE 'E11%' OR icd_code LIKE 'E13%'))
    INTERSECT DISTINCT
    SELECT hadm_id FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd`
    WHERE
        -- Filter for Heart Failure ICD codes (ICD-9: 428.xx; ICD-10: I50.xx)
        (icd_version = 9 AND icd_code LIKE '428%')
        OR (icd_version = 10 AND icd_code LIKE 'I50%')
),

-- Step 3: Create the final patient cohort by joining the base cohort with the diagnosis filter.
cohort AS (
    SELECT
        cb.subject_id,
        cb.hadm_id,
        cb.admittime,
        cb.dischtime
    FROM
        cohort_base AS cb
    INNER JOIN
        hadm_with_diagnoses AS hwd
            ON cb.hadm_id = hwd.hadm_id
),

-- Step 4: Identify all relevant medication prescriptions for the cohort and categorize them.
categorized_prescriptions AS (
    SELECT
        c.hadm_id,
        c.admittime,
        c.dischtime,
        p.starttime,
        p.stoptime,
        CASE
            WHEN LOWER(p.drug) LIKE '%insulin%' OR LOWER(p.drug) LIKE '%metformin%' OR LOWER(p.drug) LIKE '%glipizide%' OR LOWER(p.drug) LIKE '%glyburide%' OR LOWER(p.drug) LIKE '%pioglitazone%' OR LOWER(p.drug) LIKE '%rosiglitazone%' OR LOWER(p.drug) LIKE '%sitagliptin%' OR LOWER(p.drug) LIKE '%saxagliptin%' OR LOWER(p.drug) LIKE '%linagliptin%' OR LOWER(p.drug) LIKE '%alogliptin%' OR LOWER(p.drug) LIKE '%canagliflozin%' OR LOWER(p.drug) LIKE '%dapagliflozin%' OR LOWER(p.drug) LIKE '%empagliflozin%' OR LOWER(p.drug) LIKE '%exenatide%' OR LOWER(p.drug) LIKE '%liraglutide%' OR LOWER(p.drug) LIKE '%semaglutide%' THEN 'Antidiabetic'
            WHEN LOWER(p.drug) LIKE '%metoprolol%' OR LOWER(p.drug) LIKE '%carvedilol%' OR LOWER(p.drug) LIKE '%bisoprolol%' OR LOWER(p.drug) LIKE '%atenolol%' OR LOWER(p.drug) LIKE '%labetalol%' OR LOWER(p.drug) LIKE '%propranolol%' OR LOWER(p.drug) LIKE '%sotalol%' OR LOWER(p.drug) LIKE '%nebivolol%' THEN 'Beta Blocker'
            WHEN LOWER(p.drug) LIKE '%lisinopril%' OR LOWER(p.drug) LIKE '%enalapril%' OR LOWER(p.drug) LIKE '%ramipril%' OR LOWER(p.drug) LIKE '%captopril%' OR LOWER(p.drug) LIKE '%benazepril%' OR LOWER(p.drug) LIKE '%quinapril%' OR LOWER(p.drug) LIKE '%losartan%' OR LOWER(p.drug) LIKE '%valsartan%' OR LOWER(p.drug) LIKE '%irbesartan%' OR LOWER(p.drug) LIKE '%candesartan%' OR LOWER(p.drug) LIKE '%olmesartan%' OR LOWER(p.drug) LIKE '%telmisartan%' OR LOWER(p.drug) LIKE '%sacubitril%' THEN 'ACEi/ARB/ARNI'
            WHEN LOWER(p.drug) LIKE '%furosemide%' OR LOWER(p.drug) LIKE '%lasix%' OR LOWER(p.drug) LIKE '%bumetanide%' OR LOWER(p.drug) LIKE '%bumex%' OR LOWER(p.drug) LIKE '%torsemide%' OR LOWER(p.drug) LIKE '%demadex%' THEN 'Loop Diuretic'
            ELSE NULL
        END AS drug_class
    FROM
        cohort AS c
    INNER JOIN
        `physionet-data.mimiciv_3_1_hosp.prescriptions` AS p
            ON c.hadm_id = p.hadm_id
),

-- Step 5: For each patient and each drug class, determine if they were on the drug
-- during the first 72h and/or the final 72h.
patient_drug_flags AS (
    SELECT
        hadm_id,
        drug_class,
        -- Flag is 1 if any prescription overlaps with the first 72 hours
        MAX(CASE WHEN starttime <= DATETIME_ADD(admittime, INTERVAL 72 HOUR) AND stoptime >= admittime THEN 1 ELSE 0 END) AS on_in_first_72h,
        -- Flag is 1 if any prescription overlaps with the final 72 hours
        MAX(CASE WHEN starttime <= dischtime AND stoptime >= DATETIME_SUB(dischtime, INTERVAL 72 HOUR) THEN 1 ELSE 0 END) AS on_in_final_72h
    FROM
        categorized_prescriptions
    WHERE
        drug_class IS NOT NULL
    GROUP BY
        hadm_id, drug_class
),

-- Step 6: Create a base grid of every patient and every drug class for accurate denominator counting.
patient_drug_grid AS (
    SELECT
        c.hadm_id,
        dc.drug_class
    FROM
        cohort AS c
    CROSS JOIN (
        SELECT 'Antidiabetic' AS drug_class UNION ALL
        SELECT 'Beta Blocker' AS drug_class UNION ALL
        SELECT 'ACEi/ARB/ARNI' AS drug_class UNION ALL
        SELECT 'Loop Diuretic' AS drug_class
    ) AS dc
)

-- Step 7: Final aggregation to calculate percentages and counts.
SELECT
    pdg.drug_class,
    COUNT(DISTINCT pdg.hadm_id) AS total_patients_in_cohort,
    -- Percentage on medication in each window
    SAFE_DIVIDE(SUM(COALESCE(pdf.on_in_first_72h, 0)), COUNT(DISTINCT pdg.hadm_id)) * 100 AS pct_on_in_first_72h,
    SAFE_DIVIDE(SUM(COALESCE(pdf.on_in_final_72h, 0)), COUNT(DISTINCT pdg.hadm_id)) * 100 AS pct_on_in_final_72h,
    -- Counts for medication status changes
    SUM(CASE WHEN COALESCE(pdf.on_in_first_72h, 0) = 1 AND COALESCE(pdf.on_in_final_72h, 0) = 1 THEN 1 ELSE 0 END) AS continued_count,
    SUM(CASE WHEN COALESCE(pdf.on_in_first_72h, 0) = 0 AND COALESCE(pdf.on_in_final_72h, 0) = 1 THEN 1 ELSE 0 END) AS initiated_count,
    SUM(CASE WHEN COALESCE(pdf.on_in_first_72h, 0) = 1 AND COALESCE(pdf.on_in_final_72h, 0) = 0 THEN 1 ELSE 0 END) AS discontinued_count
FROM
    patient_drug_grid AS pdg
LEFT JOIN
    patient_drug_flags AS pdf
        ON pdg.hadm_id = pdf.hadm_id AND pdg.drug_class = pdf.drug_class
GROUP BY
    pdg.drug_class
ORDER BY
    pdg.drug_class;