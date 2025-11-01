WITH dka_admissions AS (
    SELECT DISTINCT
        adm.subject_id,
        adm.hadm_id,
        adm.admittime,
        adm.dischtime
    FROM
        `physionet-data.mimiciv_3_1_hosp.admissions` AS adm
    INNER JOIN
        `physionet-data.mimiciv_3_1_hosp.patients` AS pat
        ON adm.subject_id = pat.subject_id
    INNER JOIN
        `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` AS diag_icd
        ON adm.subject_id = diag_icd.subject_id AND adm.hadm_id = diag_icd.hadm_id
    WHERE
        pat.gender = 'F'
        -- Filter for DKA ICD-10 codes
        AND (
               diag_icd.icd_code LIKE 'E10.1%' -- Type 1 diabetes mellitus with ketoacidosis
            OR diag_icd.icd_code LIKE 'E11.1%' -- Type 2 diabetes mellitus with ketoacidosis
        )
),
-- Step 2: Get all serum glucose measurements
serum_glucose_measurements AS (
    SELECT
        le.subject_id,
        le.hadm_id,
        le.charttime,
        le.valuenum
    FROM
        `physionet-data.mimiciv_3_1_hosp.labevents` AS le
    INNER JOIN
        `physionet-data.mimiciv_3_1_hosp.d_labitems` AS dl
        ON le.itemid = dl.itemid
    WHERE
        -- Itemid for 'Glucose' (fluid: Blood, category: Chemistry)
        dl.itemid = 50931
        AND le.valuenum IS NOT NULL
        AND le.valuenum > 0 -- Exclude non-positive or invalid glucose values
),
-- Step 3: Find the peak serum glucose during each DKA hospitalization
peak_glucose_per_admission AS (
    SELECT
        dka.subject_id,
        dka.hadm_id,
        MAX(sgm.valuenum) AS peak_glucose_value
    FROM
        dka_admissions AS dka
    INNER JOIN
        serum_glucose_measurements AS sgm
        ON dka.subject_id = sgm.subject_id
        AND dka.hadm_id = sgm.hadm_id
    WHERE
        -- Ensure the measurement occurred within the hospital admission timeframe
        sgm.charttime BETWEEN dka.admittime AND dka.dischtime
    GROUP BY
        dka.subject_id,
        dka.hadm_id
)
-- Step 4: Calculate the median of these peak glucose values
SELECT
    PERCENTILE_CONT(peak_glucose_value, 0.5) OVER() AS median_peak_serum_glucose
FROM
    peak_glucose_per_admission
LIMIT 1; -- PERCENTILE_CONT with OVER() returns the same value for all rows, so we only need one.;