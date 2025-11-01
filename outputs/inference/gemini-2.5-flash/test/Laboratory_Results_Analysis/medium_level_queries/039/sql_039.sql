WITH admission_cohort AS (
    -- Step 1: Identify eligible female patients aged 87-97 admitted with chest pain
    SELECT DISTINCT
        adm.subject_id,
        adm.hadm_id
    FROM
        `physionet-data.mimiciv_3_1_hosp.admissions` AS adm
    INNER JOIN
        `physionet-data.mimiciv_3_1_hosp.patients` AS pat
        ON adm.subject_id = pat.subject_id
    INNER JOIN
        `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` AS diag
        ON adm.subject_id = diag.subject_id AND adm.hadm_id = diag.hadm_id
    WHERE
        pat.gender = 'F'
        AND pat.anchor_age BETWEEN 87 AND 97
        AND diag.icd_code LIKE 'R07%' -- ICD-10 codes for chest pain
        AND diag.seq_num = 1 -- Assuming primary diagnosis for "admitted with chest pain"
),
first_hs_tnt AS (
    -- Step 2: Get the first high-sensitivity Troponin T (hs-TnT) value for each eligible admission
    SELECT
        ac.subject_id,
        ac.hadm_id,
        le.valuenum AS hs_tnt_value,
        ROW_NUMBER() OVER (PARTITION BY ac.subject_id, ac.hadm_id ORDER BY le.charttime ASC) AS rn
    FROM
        admission_cohort AS ac
    INNER JOIN
        `physionet-data.mimiciv_3_1_hosp.labevents` AS le
        ON ac.subject_id = le.subject_id AND ac.hadm_id = le.hadm_id
    WHERE
        le.itemid = 229344 -- itemid for Troponin T, High Sensitivity
        AND le.valuenum IS NOT NULL
        AND le.valuenum >= 0 -- Ensure valid numeric value
)
-- Step 3 & 4: Categorize hs-TnT levels and calculate statistics
SELECT
    CASE
        WHEN tnt.hs_tnt_value <= 0.04 THEN 'Normal (<= 0.04)'
        WHEN tnt.hs_tnt_value > 0.04 AND tnt.hs_tnt_value <= 0.1 THEN 'Borderline (0.04 - 0.1)'
        ELSE 'Injury (> 0.1)'
    END AS hs_tnt_category,
    COUNT(tnt.hs_tnt_value) AS category_count,
    ROUND(CAST(COUNT(tnt.hs_tnt_value) AS BIGNUMERIC) * 100 / (SELECT COUNT(*) FROM first_hs_tnt WHERE rn = 1), 2) AS percentage,
    ROUND(AVG(tnt.hs_tnt_value), 4) AS mean_hs_tnt,
    ROUND(APPROX_QUANTILES(tnt.hs_tnt_value, 4)[OFFSET(2)], 4) AS median_hs_tnt, -- 50th percentile
    ROUND(APPROX_QUANTILES(tnt.hs_tnt_value, 4)[OFFSET(1)], 4) AS q1_hs_tnt,   -- 25th percentile
    ROUND(APPROX_QUANTILES(tnt.hs_tnt_value, 4)[OFFSET(3)], 4) AS q3_hs_tnt,   -- 75th percentile
    ROUND(APPROX_QUANTILES(tnt.hs_tnt_value, 4)[OFFSET(3)] - APPROX_QUANTILES(tnt.hs_tnt_value, 4)[OFFSET(1)], 4) AS iqr_hs_tnt
FROM
    first_hs_tnt AS tnt
WHERE
    tnt.rn = 1 -- Select only the first hs-TnT measurement for each admission
GROUP BY
    hs_tnt_category
ORDER BY
    CASE hs_tnt_category
        WHEN 'Normal (<= 0.04)' THEN 1
        WHEN 'Borderline (0.04 - 0.1)' THEN 2
        ELSE 3
    END;