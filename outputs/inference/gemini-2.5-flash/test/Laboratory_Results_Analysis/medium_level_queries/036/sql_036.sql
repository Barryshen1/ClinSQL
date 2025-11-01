WITH admissions_cohort AS (
    -- Step 1: Identify the target patient cohort (male, age 77-87, primary diagnosis of AMI)
    SELECT
        ad.subject_id,
        ad.hadm_id
    FROM
        `physionet-data.mimiciv_3_1_hosp`.admissions ad
    JOIN
        `physionet-data.mimiciv_3_1_hosp`.patients pat
        ON ad.subject_id = pat.subject_id
    JOIN
        `physionet-data.mimiciv_3_1_hosp`.diagnoses_icd di
        ON ad.hadm_id = di.hadm_id
    WHERE
        pat.gender = 'M'
        AND pat.anchor_age BETWEEN 77 AND 87
        AND di.seq_num = 1 -- Primary diagnosis
        AND (
            (di.icd_version = 9 AND di.icd_code LIKE '410.%') -- ICD-9 codes for AMI
            OR (di.icd_version = 10 AND di.icd_code BETWEEN 'I21.0' AND 'I21.9') -- ICD-10 codes for AMI
        )
    GROUP BY -- Ensure each admission in the cohort is unique
        ad.subject_id, ad.hadm_id
),
first_hs_tnt AS (
    -- Step 2: Find the initial hs-TnT lab measurement for each admission in the cohort
    SELECT
        ac.subject_id,
        ac.hadm_id,
        le.valuenum,
        ROW_NUMBER() OVER (PARTITION BY ac.hadm_id ORDER BY le.charttime, le.labevent_id) as rn
    FROM
        admissions_cohort ac
    JOIN
        `physionet-data.mimiciv_3_1_hosp`.labevents le
        ON ac.subject_id = le.subject_id AND ac.hadm_id = le.hadm_id
    WHERE
        le.itemid = 50987 -- itemid for "Troponin T, High Sensitivity"
        AND le.valuenum IS NOT NULL -- Exclude records without a numeric value
        AND le.valuenum >= 0 -- Ensure valid positive measurement
),
initial_hs_tnt_value AS (
    -- Step 3: Select only the very first hs-TnT measurement for each admission
    SELECT
        subject_id,
        hadm_id,
        valuenum AS initial_tnt_value
    FROM
        first_hs_tnt
    WHERE
        rn = 1
),
classified_tnt AS (
    -- Step 4: Classify the initial hs-TnT value based on common clinical thresholds
    SELECT
        hadm_id,
        initial_tnt_value,
        CASE
            WHEN initial_tnt_value < 5 THEN 'Normal (< 5 ng/L)'
            WHEN initial_tnt_value >= 5 AND initial_tnt_value < 15 THEN 'Borderline (5 - 14 ng/L)'
            WHEN initial_tnt_value >= 15 THEN 'Myocardial Injury (>= 15 ng/L)'
            ELSE 'Other/Unknown' -- Fallback, though not expected given valuenum checks
        END AS tnt_category
    FROM
        initial_hs_tnt_value
)
-- Step 5: Calculate the distribution (counts and percentages) for each category
SELECT
    tnt_category,
    COUNT(DISTINCT hadm_id) AS cohort_count,
    ROUND(COUNT(DISTINCT hadm_id) * 100.0 / SUM(COUNT(DISTINCT hadm_id)) OVER (), 2) AS percentage
FROM
    classified_tnt
GROUP BY
    tnt_category
ORDER BY
    -- Order the categories logically for presentation
    CASE tnt_category
        WHEN 'Normal (< 5 ng/L)' THEN 1
        WHEN 'Borderline (5 - 14 ng/L)' THEN 2
        WHEN 'Myocardial Injury (>= 15 ng/L)' THEN 3
        ELSE 4
    END;