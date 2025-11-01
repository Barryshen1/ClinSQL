WITH patient_cohort AS (
    -- Step 1: Identify female patients aged 82-92
    SELECT
        p.subject_id,
        p.gender,
        p.anchor_age,
        adm.hadm_id,
        adm.admittime
    FROM
        `physionet-data.mimiciv_3_1_hosp.patients` p
    INNER JOIN
        `physionet-data.mimiciv_3_1_hosp.admissions` adm
        ON p.subject_id = adm.subject_id
    WHERE
        p.gender = 'F'
        AND p.anchor_age BETWEEN 82 AND 92
),
admissions_with_diagnosis AS (
    -- Step 2: Filter these admissions for diagnoses of Chest Pain or AMI
    SELECT DISTINCT
        pc.subject_id,
        pc.hadm_id
    FROM
        patient_cohort pc
    INNER JOIN
        `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` di
        ON pc.subject_id = di.subject_id AND pc.hadm_id = di.hadm_id
    WHERE
        (
            -- ICD-9 codes for Acute Myocardial Infarction
            (di.icd_version = 9 AND di.icd_code BETWEEN '4100' AND '4109')
            -- ICD-10 codes for Acute Myocardial Infarction
            OR (di.icd_version = 10 AND di.icd_code LIKE 'I21%')
            -- ICD-9 codes for Chest Pain (786.5x)
            OR (di.icd_version = 9 AND di.icd_code LIKE '7865%')
            -- ICD-10 codes for Chest Pain (R07.x)
            OR (di.icd_version = 10 AND di.icd_code LIKE 'R07%')
        )
),
initial_troponin_measurements AS (
    -- Step 3: Find the first Troponin T measurement for each qualifying admission
    -- No filtering on value here; we find the absolute first measurement.
    SELECT
        ad.subject_id,
        ad.hadm_id,
        le.valuenum AS initial_troponin_t_value,
        ROW_NUMBER() OVER (PARTITION BY ad.hadm_id ORDER BY le.charttime) AS rn
    FROM
        admissions_with_diagnosis ad
    INNER JOIN
        `physionet-data.mimiciv_3_1_hosp.labevents` le
        ON ad.subject_id = le.subject_id AND ad.hadm_id = le.hadm_id
    INNER JOIN
        `physionet-data.mimiciv_3_1_hosp.d_labitems` dli
        ON le.itemid = dli.itemid
    WHERE
        dli.label = 'Troponin T' -- Specific lab item for Troponin T
        AND le.valuenum IS NOT NULL -- Ensure numeric value exists
        AND le.valueuom = 'ng/mL' -- Ensure the unit is correct
),
filtered_admissions_with_initial_troponin AS (
    -- Step 4: Filter for the first valid measurement (rn = 1) and
    -- apply the condition that this initial value must be > 0.01 ng/mL
    SELECT
        initial_troponin_t_value
    FROM
        initial_troponin_measurements
    WHERE
        rn = 1 -- Select only the first measurement per admission
        AND initial_troponin_t_value > 0.01 -- Now apply the threshold for the *initial* value
)
-- Step 5: Calculate statistics (p25, p50, p75, min-max)
-- All aggregate functions are now explicitly window functions
SELECT
    MIN(initial_troponin_t_value) OVER () AS min_troponin_t,
    MAX(initial_troponin_t_value) OVER () AS max_troponin_t,
    PERCENTILE_CONT(initial_troponin_t_value, 0.25) OVER () AS p25_troponin_t,
    PERCENTILE_CONT(initial_troponin_t_value, 0.50) OVER () AS p50_troponin_t,
    PERCENTILE_CONT(initial_troponin_t_value, 0.75) OVER () AS p75_troponin_t
FROM
    filtered_admissions_with_initial_troponin
LIMIT 1; -- Add LIMIT 1 since these are global aggregates and we only need one row of results;