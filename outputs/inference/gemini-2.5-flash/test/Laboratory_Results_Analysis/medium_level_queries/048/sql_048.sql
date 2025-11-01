WITH ami_admissions AS (
    -- Step 1: Identify admissions with AMI diagnoses
    SELECT DISTINCT
        ad.subject_id,
        ad.hadm_id
    FROM
        `physionet-data.mimiciv_3_1_hosp.admissions` AS ad
    INNER JOIN
        `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` AS diag
        ON ad.subject_id = diag.subject_id AND ad.hadm_id = diag.hadm_id
    WHERE
        -- ICD-9 codes for AMI (410.xx)
        (diag.icd_version = 9 AND diag.icd_code LIKE '410%')
        OR
        -- ICD-10 codes for AMI (I21.xx, I22.xx)
        (diag.icd_version = 10 AND (diag.icd_code LIKE 'I21%' OR diag.icd_code LIKE 'I22%'))
),
eligible_cohort AS (
    -- Step 2: Filter for female patients aged 55-65
    SELECT
        ami.subject_id,
        ami.hadm_id
    FROM
        ami_admissions AS ami
    INNER JOIN
        `physionet-data.mimiciv_3_1_hosp.patients` AS pat
        ON ami.subject_id = pat.subject_id
    WHERE
        pat.gender = 'F'
        AND pat.anchor_age BETWEEN 55 AND 65
),
first_hs_tnt_values AS (
    -- Step 3 & 4: Get the first hs-TnT value > 0.01 ng/mL for each eligible admission, ordered by charttime
    SELECT
        ec.subject_id,
        ec.hadm_id,
        le.valuenum AS hs_tnt_value,
        ROW_NUMBER() OVER (PARTITION BY ec.hadm_id ORDER BY le.charttime) AS rn
    FROM
        eligible_cohort AS ec
    INNER JOIN
        `physionet-data.mimiciv_3_1_hosp.labevents` AS le
        ON ec.subject_id = le.subject_id AND ec.hadm_id = le.hadm_id
    INNER JOIN
        `physionet-data.mimiciv_3_1_hosp.d_labitems` AS dli
        ON le.itemid = dli.itemid
    WHERE
        -- Specific ITEMID for 'Troponin T, High Sensitivity' (common in MIMIC-IV for hs-TnT), itemid '51003' is "Troponin T, High Sensitivity" in d_labitems.
        dli.itemid = 51003
        AND le.valuenum IS NOT NULL
        AND le.valuenum > 0.01 -- Filter for values > 0.01 ng/mL as specified
),
filtered_first_hs_tnt AS (
    -- Select only the first hs-TnT value for each admission
    SELECT
        subject_id,
        hadm_id,
        hs_tnt_value
    FROM
        first_hs_tnt_values
    WHERE
        rn = 1
)
-- Step 5: Calculate and report statistics for the first filtered hs-TnT value
SELECT
    COUNT(DISTINCT fht.subject_id) AS patient_count,
    COUNT(DISTINCT fht.hadm_id) AS admission_count,
    AVG(fht.hs_tnt_value) AS mean_hs_tnt_ng_per_ml,
    -- Corrected BigQuery syntax for PERCENTILE_CONT as an aggregate function
    PERCENTILE_CONT(fht.hs_tnt_value, 0.5) AS median_hs_tnt_ng_per_ml,
    PERCENTILE_CONT(fht.hs_tnt_value, 0.25) AS q1_hs_tnt_ng_per_ml,
    PERCENTILE_CONT(fht.hs_tnt_value, 0.75) AS q3_hs_tnt_ng_per_ml,
    (PERCENTILE_CONT(fht.hs_tnt_value, 0.75) - PERCENTILE_CONT(fht.hs_tnt_value, 0.25)) AS iqr_hs_tnt_ng_per_ml
FROM
    filtered_first_hs_tnt AS fht;