WITH
-- Step 1: Identify the full cohort of hospital admissions for 60-70 year old females
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
        AND p.anchor_age BETWEEN 60 AND 70
),

-- Step 2: Filter the cohort for patients with both T2DM and HF diagnoses
cohort_with_dx AS (
    SELECT
        hadm_id,
        MAX(
            CASE
                WHEN (icd_version = 9 AND SUBSTR(icd_code, 1, 3) = '250' AND SUBSTR(icd_code, 5, 1) IN ('0', '2'))
                    OR (icd_version = 10 AND SUBSTR(icd_code, 1, 3) = 'E11')
                THEN 1
                ELSE 0
            END
        ) AS has_t2dm,
        MAX(
            CASE
                WHEN (icd_version = 9 AND SUBSTR(icd_code, 1, 3) = '428')
                    OR (icd_version = 10 AND SUBSTR(icd_code, 1, 3) = 'I50')
                THEN 1
                ELSE 0
            END
        ) AS has_hf
    FROM
        `physionet-data.mimiciv_3_1_hosp.diagnoses_icd`
    WHERE
        hadm_id IN (SELECT hadm_id FROM cohort_base)
    GROUP BY
        hadm_id
),

-- Step 3: Create the final cohort of admissions with valid time windows
final_cohort AS (
    SELECT
        cb.hadm_id,
        cb.admittime,
        cb.dischtime
    FROM
        cohort_base AS cb
    INNER JOIN
        cohort_with_dx AS cdx
            ON cb.hadm_id = cdx.hadm_id
    WHERE
        cdx.has_t2dm = 1 AND cdx.has_hf = 1
        AND cb.admittime IS NOT NULL AND cb.dischtime IS NOT NULL
),

-- Step 4: Classify all prescriptions for the final cohort into drug classes
classified_prescriptions AS (
    SELECT
        pr.hadm_id,
        pr.starttime,
        CASE
            -- Antidiabetics
            WHEN
                LOWER(pr.drug) LIKE '%insulin%' OR LOWER(pr.drug) LIKE 'metformin%' OR LOWER(pr.drug) LIKE 'glipizide%'
                OR LOWER(pr.drug) LIKE 'glyburide%' OR LOWER(pr.drug) LIKE 'pioglitazone%' OR LOWER(pr.drug) LIKE 'rosiglitazone%'
                OR LOWER(pr.drug) LIKE 'sitagliptin%' OR LOWER(pr.drug) LIKE 'saxagliptin%' OR LOWER(pr.drug) LIKE 'linagliptin%'
                OR LOWER(pr.drug) LIKE 'alogliptin%' OR LOWER(pr.drug) LIKE 'canagliflozin%' OR LOWER(pr.drug) LIKE 'dapagliflozin%'
                OR LOWER(pr.drug) LIKE 'empagliflozin%' OR LOWER(pr.drug) LIKE 'exenatide%' OR LOWER(pr.drug) LIKE 'liraglutide%'
                OR LOWER(pr.drug) LIKE 'semaglutide%' OR LOWER(pr.drug) LIKE 'nateglinide%' OR LOWER(pr.drug) LIKE 'repaglinide%'
                THEN 'Antidiabetics'
            -- Beta-blockers
            WHEN
                LOWER(pr.drug) LIKE 'metoprolol%' OR LOWER(pr.drug) LIKE 'carvedilol%' OR LOWER(pr.drug) LIKE 'labetalol%'
                OR LOWER(pr.drug) LIKE 'atenolol%' OR LOWER(pr.drug) LIKE 'esmolol%' OR LOWER(pr.drug) LIKE 'bisoprolol%'
                OR LOWER(pr.drug) LIKE 'propranolol%' OR LOWER(pr.drug) LIKE 'sotalol%'
                THEN 'Beta-blockers'
            -- ACEi/ARB/ARNI
            WHEN
                LOWER(pr.drug) LIKE '%pril' OR LOWER(pr.drug) LIKE '%sartan' OR LOWER(pr.drug) LIKE '%sacubitril%'
                OR LOWER(pr.drug) LIKE 'entresto%'
                THEN 'ACEi/ARB/ARNI'
            -- Loop Diuretics
            WHEN
                LOWER(pr.drug) LIKE 'furosemide%' OR LOWER(pr.drug) LIKE 'lasix%' OR LOWER(pr.drug) LIKE 'bumetanide%'
                OR LOWER(pr.drug) LIKE 'bumex%' OR LOWER(pr.drug) LIKE 'torsemide%'
                THEN 'Loop Diuretics'
            ELSE NULL
        END AS drug_class
    FROM
        `physionet-data.mimiciv_3_1_hosp.prescriptions` AS pr
    WHERE
        pr.hadm_id IN (SELECT hadm_id FROM final_cohort) AND pr.starttime IS NOT NULL
),

-- Step 5: For each patient and drug class, flag if it was given in the defined windows
patient_drug_flags AS (
    SELECT
        cp.hadm_id,
        cp.drug_class,
        MAX(CASE WHEN cp.starttime BETWEEN fc.admittime AND TIMESTAMP_ADD(fc.admittime, INTERVAL 48 HOUR) THEN TRUE ELSE FALSE END) AS given_in_first_48h,
        MAX(CASE WHEN cp.starttime BETWEEN TIMESTAMP_SUB(fc.dischtime, INTERVAL 24 HOUR) AND fc.dischtime THEN TRUE ELSE FALSE END) AS given_in_final_24h
    FROM
        classified_prescriptions AS cp
    INNER JOIN
        final_cohort AS fc
            ON cp.hadm_id = fc.hadm_id
    WHERE
        cp.drug_class IS NOT NULL
    GROUP BY
        cp.hadm_id, cp.drug_class
),

-- Step 6: Create a scaffold of the drug classes to ensure all are reported
drug_classes AS (
    SELECT 'Antidiabetics' AS drug_class UNION ALL
    SELECT 'Beta-blockers' UNION ALL
    SELECT 'ACEi/ARB/ARNI' UNION ALL
    SELECT 'Loop Diuretics'
),

-- Step 7: Get the total number of patients in the cohort for the denominator
cohort_size AS (
    SELECT COUNT(hadm_id) AS total FROM final_cohort
)

-- Final Step: Calculate and present the final statistics
SELECT
    dc.drug_class,
    -- Calculate the percentage of patients receiving the drug in the first 48 hours
    SAFE_DIVIDE(
        COUNT(DISTINCT CASE WHEN pdf.given_in_first_48h THEN pdf.hadm_id ELSE NULL END),
        cs.total
    ) * 100 AS first_48h_initiation_pct,

    -- Calculate the percentage of patients receiving the drug in the final 24 hours
    SAFE_DIVIDE(
        COUNT(DISTINCT CASE WHEN pdf.given_in_final_24h THEN pdf.hadm_id ELSE NULL END),
        cs.total
    ) * 100 AS final_24h_initiation_pct,

    -- Calculate the absolute difference in percentage points
    (
        SAFE_DIVIDE(
            COUNT(DISTINCT CASE WHEN pdf.given_in_final_24h THEN pdf.hadm_id ELSE NULL END),
            cs.total
        ) * 100
    ) - (
        SAFE_DIVIDE(
            COUNT(DISTINCT CASE WHEN pdf.given_in_first_48h THEN pdf.hadm_id ELSE NULL END),
            cs.total
        ) * 100
    ) AS absolute_difference_pp
FROM
    drug_classes AS dc
CROSS JOIN
    cohort_size AS cs
LEFT JOIN
    patient_drug_flags AS pdf
        ON dc.drug_class = pdf.drug_class
GROUP BY
    dc.drug_class,
    cs.total
ORDER BY
    dc.drug_class;