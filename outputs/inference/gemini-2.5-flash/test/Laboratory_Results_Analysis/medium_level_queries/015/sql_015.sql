WITH acs_admissions AS (
    -- Step 1: Identify admissions with an ACS diagnosis
    SELECT DISTINCT
        da.subject_id,
        da.hadm_id,
        adm.admittime,
        pat.gender,
        pat.anchor_age
    FROM
        `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` AS da
    INNER JOIN
        `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` AS did
        ON da.icd_code = did.icd_code AND da.icd_version = did.icd_version
    INNER JOIN
        `physionet-data.mimiciv_3_1_hosp.admissions` AS adm
        ON da.subject_id = adm.subject_id AND da.hadm_id = adm.hadm_id
    INNER JOIN
        `physionet-data.mimiciv_3_1_hosp.patients` AS pat
        ON da.subject_id = pat.subject_id
    WHERE
        -- ICD-9 codes for Acute Coronary Syndrome (ACS)
        (da.icd_version = 9 AND (
            SUBSTR(da.icd_code, 1, 3) IN ('410', '411', '412', '413') OR da.icd_code IN ('41400', '41401', '41406')
        ))
        OR
        -- ICD-10 codes for Acute Coronary Syndrome (ACS)
        (da.icd_version = 10 AND (
            SUBSTR(da.icd_code, 1, 3) IN ('I20', 'I21', 'I22', 'I24') OR SUBSTR(da.icd_code, 1, 4) = 'I251'
        ))
),
filtered_cohort AS (
    -- Step 2: Filter by demographics
    SELECT
        acs.subject_id,
        acs.hadm_id,
        acs.admittime
    FROM
        acs_admissions AS acs
    WHERE
        acs.gender = 'F'
        -- MIMIC-IV caps anchor_age at 91 for all patients >= 90 years old.
        -- So, to include patients aged 88-98, we select anchor_age between 88 and 91.
        AND acs.anchor_age BETWEEN 88 AND 91
),
troponin_t_labs AS (
    -- Step 3: Get all relevant Troponin T lab events for the filtered cohort
    SELECT
        fc.subject_id,
        fc.hadm_id,
        le.charttime,
        CAST(le.valuenum AS BIGNUMERIC) AS valuenum, -- Cast to BIGNUMERIC for precision
        le.valueuom
    FROM
        filtered_cohort AS fc
    INNER JOIN
        `physionet-data.mimiciv_3_1_hosp.labevents` AS le
        ON fc.subject_id = le.subject_id AND fc.hadm_id = le.hadm_id
    INNER JOIN
        `physionet-data.mimiciv_3_1_hosp.d_labitems` AS dli
        ON le.itemid = dli.itemid
    WHERE
        dli.label = 'Troponin T' -- Specific item for Troponin T
        AND le.valuenum IS NOT NULL
        AND le.valuenum > 0.01 -- Initial Troponin T must be > 0.01 ng/mL
        AND le.valueuom = 'ng/mL' -- Ensure correct units
        -- Lab events can have charttime before admittime if from ED, which is fine for "initial".
),
first_troponin_t_per_admission AS (
    -- Step 4: Find the first qualifying Troponin T value for each eligible admission
    SELECT
        subject_id,
        hadm_id,
        valuenum AS first_troponin_t_value,
        ROW_NUMBER() OVER (PARTITION BY subject_id, hadm_id ORDER BY charttime ASC) AS rn
    FROM
        troponin_t_labs
)
-- Step 5: Calculate Median and IQR using PERCENTILE_CONT as an analytic function
SELECT
    ROUND(CAST(PERCENTILE_CONT(first_troponin_t_value, 0.5) OVER (ORDER BY first_troponin_t_value) AS NUMERIC), 4) AS median_troponin_t_ng_per_ml,
    ROUND(CAST(PERCENTILE_CONT(first_troponin_t_value, 0.75) OVER (ORDER BY first_troponin_t_value) AS NUMERIC), 4) -
    ROUND(CAST(PERCENTILE_CONT(first_troponin_t_value, 0.25) OVER (ORDER BY first_troponin_t_value) AS NUMERIC), 4) AS iqr_troponin_t_ng_per_ml
FROM
    first_troponin_t_per_admission
WHERE
    rn = 1
LIMIT 1; -- LIMIT to 1 because analytic functions return a value for every row.;