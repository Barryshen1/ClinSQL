WITH troponin_itemid AS (
    -- Step 1: Identify the itemid for high-sensitivity Troponin T
    SELECT itemid
    FROM `physionet-data.mimiciv_3_1_hosp.d_labitems`
    WHERE
        LOWER(label) LIKE '%troponin t%'
        AND (LOWER(label) LIKE '%hs%' OR LOWER(label) LIKE '%high sensitivity%')
    LIMIT 1 -- Assuming there's one primary itemid for this specific test
),
cohort_admissions AS (
    -- Step 2: Select female patients aged 36-46 admitted with Ischemic Heart Disease
    SELECT DISTINCT
        adm.subject_id,
        adm.hadm_id,
        adm.admittime
    FROM `physionet-data.mimiciv_3_1_hosp.admissions` AS adm
    JOIN `physionet-data.mimiciv_3_1_hosp.patients` AS pat
        ON adm.subject_id = pat.subject_id
    JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` AS diag
        ON adm.hadm_id = diag.hadm_id
    WHERE
            pat.gender = 'F'
        AND pat.anchor_age BETWEEN 36 AND 46
        -- Filter for Ischemic Heart Disease ICD codes (ICD-9: 410-414, ICD-10: I20-I25)
        AND (
               (diag.icd_version = 9 AND SUBSTR(diag.icd_code, 1, 3) BETWEEN '410' AND '414')
            OR (diag.icd_version = 10 AND SUBSTR(diag.icd_code, 1, 3) BETWEEN 'I20' AND 'I25')
        )
),
first_troponin_t_for_cohort AS (
    -- Step 3: Get the first recorded high-sensitivity Troponin T value for each admission in the cohort
    SELECT
        le.subject_id,
        le.hadm_id,
        le.valuenum,
        le.ref_range_upper,
        ROW_NUMBER() OVER (PARTITION BY le.subject_id, le.hadm_id ORDER BY le.charttime) AS rn
    FROM `physionet-data.mimiciv_3_1_hosp.labevents` AS le
    JOIN cohort_admissions AS ca
        ON le.subject_id = ca.subject_id AND le.hadm_id = ca.hadm_id
    JOIN troponin_itemid AS ti
        ON le.itemid = ti.itemid
    WHERE
            le.valuenum IS NOT NULL -- Ensure a numeric value exists
        AND le.ref_range_upper IS NOT NULL -- Ensure upper limit of normal exists
        AND le.charttime >= ca.admittime -- Ensure lab value is recorded during or after admission
),
filtered_initial_troponin AS (
    -- Step 4: Filter for initial Troponin T values that are greater than the Upper Limit of Normal (ULN)
    SELECT
        valuenum
    FROM first_troponin_t_for_cohort
    WHERE
            rn = 1 -- Select only the first measurement
        AND valuenum > ref_range_upper -- Ensure the value is above ULN
)
-- Step 5: Calculate the requested statistics (p25, p50, p75, min, max)
SELECT
    MIN(valuenum) AS min_initial_trop_t_gt_uln,
    -- Use APPROX_QUANTILES for percentiles as PERCENTILE_CONT is not supported
    APPROX_QUANTILES(valuenum, 100)[OFFSET(25)] AS p25_initial_trop_t_gt_uln,
    APPROX_QUANTILES(valuenum, 100)[OFFSET(50)] AS p50_initial_trop_t_gt_uln,
    APPROX_QUANTILES(valuenum, 100)[OFFSET(75)] AS p75_initial_trop_t_gt_uln,
    MAX(valuenum) AS max_initial_trop_t_gt_uln
FROM filtered_initial_troponin;