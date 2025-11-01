WITH
-- Step 1: Identify admissions for male patients aged 41-51 with a diagnosis of chest pain or AMI.
cohort_admissions AS (
    SELECT DISTINCT
        adm.hadm_id
    FROM `physionet-data.mimiciv_3_1_hosp.admissions` AS adm
    INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` AS pat
        ON adm.subject_id = pat.subject_id
    INNER JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` AS diag
        ON adm.hadm_id = diag.hadm_id
    WHERE
        -- Filter for male patients
        pat.gender = 'M'
        -- Calculate and filter for age at admission between 41 and 51
        AND (EXTRACT(YEAR FROM adm.admittime) - pat.anchor_year) + pat.anchor_age BETWEEN 41 AND 51
        -- Filter for relevant diagnoses (Chest Pain or Acute Myocardial Infarction)
        AND (
            (diag.icd_version = 9 AND (STARTS_WITH(diag.icd_code, '410') OR STARTS_WITH(diag.icd_code, '786.5')))
            OR (diag.icd_version = 10 AND (STARTS_WITH(diag.icd_code, 'I21') OR STARTS_WITH(diag.icd_code, 'R07')))
        )
),

-- Step 2: For the cohort, find the first Troponin T measurement for each admission.
initial_troponin AS (
    SELECT
        le.hadm_id,
        le.valuenum,
        -- Assign a row number to each lab test for a given admission, ordered by time
        ROW_NUMBER() OVER(PARTITION BY le.hadm_id ORDER BY le.charttime) as rn
    FROM `physionet-data.mimiciv_3_1_hosp.labevents` AS le
    INNER JOIN cohort_admissions AS ca
        ON le.hadm_id = ca.hadm_id
    WHERE
        le.itemid = 51003 -- itemid for Troponin T
        AND le.valuenum IS NOT NULL -- Ensure the value is numeric
),

-- Step 3: Categorize the initial Troponin T values based on clinical thresholds.
categorized_troponin AS (
    SELECT
        valuenum,
        CASE
            WHEN valuenum < 0.01 THEN 'Normal'
            WHEN valuenum >= 0.01 AND valuenum <= 0.03 THEN 'Borderline'
            WHEN valuenum > 0.03 THEN 'Elevated'
            ELSE 'Other' -- Should not be populated given the filters
        END AS troponin_category
    FROM initial_troponin
    WHERE
        rn = 1 -- Select only the first measurement
)

-- Step 4: Calculate final statistics (counts, percentages, mean, median, IQR) for each category.
SELECT
    troponin_category,
    COUNT(*) AS count_admissions,
    SAFE_DIVIDE(COUNT(*), SUM(COUNT(*)) OVER()) * 100 AS percentage_of_total,
    AVG(valuenum) AS mean_troponin_t,
    APPROX_QUANTILES(valuenum, 100)[OFFSET(50)] AS median_troponin_t,
    APPROX_QUANTILES(valuenum, 100)[OFFSET(75)] - APPROX_QUANTILES(valuenum, 100)[OFFSET(25)] AS iqr_troponin_t
FROM categorized_troponin
WHERE
    troponin_category != 'Other'
GROUP BY
    troponin_category
ORDER BY
    -- Order logically by severity
    CASE
        WHEN troponin_category = 'Normal' THEN 1
        WHEN troponin_category = 'Borderline' THEN 2
        WHEN troponin_category = 'Elevated' THEN 3
    END;