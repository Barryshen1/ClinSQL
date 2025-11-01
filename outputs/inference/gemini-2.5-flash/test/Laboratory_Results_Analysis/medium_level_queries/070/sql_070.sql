WITH MaleElderlyChestPainAdmissions AS (
    -- Step 1: Identify male patients aged 90-100 with an admission for chest pain
    SELECT DISTINCT
        pat.subject_id,
        adm.hadm_id
    FROM
        `physionet-data.mimiciv_3_1_hosp.patients` pat
    INNER JOIN
        `physionet-data.mimiciv_3_1_hosp.admissions` adm
        ON pat.subject_id = adm.subject_id
    INNER JOIN
        `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` dicd
        ON adm.hadm_id = dicd.hadm_id AND pat.subject_id = dicd.subject_id
    INNER JOIN
        `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` d_dicd
        ON dicd.icd_code = d_dicd.icd_code AND dicd.icd_version = d_dicd.icd_version
    WHERE
        pat.gender = 'M'
        AND pat.anchor_age >= 90 -- MIMIC-IV caps age >= 90 to 91. This captures the 90-100 range.
        AND (
            d_dicd.long_title LIKE '%Chest pain%'
            OR dicd.icd_code LIKE 'R07.%' -- R07 codes for chest pain (ICD-10)
        )
),
TroponinIResults AS (
    -- Step 2: Retrieve all Troponin I measurements for these patients during their relevant admissions
    SELECT
        mecpa.subject_id,
        mecpa.hadm_id,
        le.charttime,
        le.valuenum,
        le.ref_range_upper
    FROM
        MaleElderlyChestPainAdmissions mecpa
    INNER JOIN
        `physionet-data.mimiciv_3_1_hosp.labevents` le
        ON mecpa.subject_id = le.subject_id AND mecpa.hadm_id = le.hadm_id
    INNER JOIN
        `physionet-data.mimiciv_3_1_hosp.d_labitems` dli
        ON le.itemid = dli.itemid
    WHERE
        dli.label LIKE '%Troponin I%' -- Common labels include 'Troponin I' or 'Troponin I, Quant'
        AND dli.category = 'Chemistry'
        AND le.valuenum IS NOT NULL -- Ensure a numeric value exists
        AND le.ref_range_upper IS NOT NULL -- Ensure an upper reference range exists for comparison
        AND le.valuenum >= 0 -- Troponin I values are usually non-negative
),
FirstElevatedTroponinI AS (
    -- Step 3: Identify the first elevated Troponin I measurement for each admission
    SELECT
        subject_id,
        hadm_id,
        valuenum AS initial_troponin_i_value
    FROM (
        SELECT
            subject_id,
            hadm_id,
            charttime,
            valuenum,
            ref_range_upper,
            ROW_NUMBER() OVER (PARTITION BY subject_id, hadm_id ORDER BY charttime ASC) as rn
        FROM
            TroponinIResults
    ) AS ranked_troponin
    WHERE
        rn = 1 -- Select the first measurement for the admission
        AND valuenum > ref_range_upper -- The first measurement must be elevated based on its reference range
)
-- Step 4: Calculate the required percentiles and range
SELECT
    MIN(initial_troponin_i_value) AS min_troponin_i,
    PERCENTILE_CONT(initial_troponin_i_value, 0.25) AS p25_troponin_i, -- Fix: Removed OVER() clause
    PERCENTILE_CONT(initial_troponin_i_value, 0.50) AS p50_troponin_i, -- Fix: Removed OVER() clause
    PERCENTILE_CONT(initial_troponin_i_value, 0.75) AS p75_troponin_i, -- Fix: Removed OVER() clause
    MAX(initial_troponin_i_value) AS max_troponin_i,
    (MAX(initial_troponin_i_value) - MIN(initial_troponin_i_value)) AS range_troponin_i
FROM
    FirstElevatedTroponinI;