WITH SepsisAdmissions AS (
    -- Step 1 & 2: Identify male patients aged 83 with sepsis admissions
    SELECT DISTINCT
        p.subject_id,
        adm.hadm_id
    FROM
        `physionet-data.mimiciv_3_1_hosp.patients` p
    INNER JOIN
        `physionet-data.mimiciv_3_1_hosp.admissions` adm
        ON p.subject_id = adm.subject_id
    INNER JOIN
        `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` di
        ON adm.hadm_id = di.hadm_id
    WHERE
        p.gender = 'M'
        AND p.anchor_age = 83 -- Filter for 83-year-old men
        AND (
            -- Sepsis diagnosis criteria (common ICD-10 and ICD-9 codes)
            (di.icd_version = 10 AND (di.icd_code LIKE 'R65.2%' OR di.icd_code LIKE 'A40%' OR di.icd_code LIKE 'A41%'))
            OR
            (di.icd_version = 9 AND (di.icd_code LIKE '99592' OR di.icd_code LIKE '78552'))
        )
),
FirstCreatinine AS (
    -- Step 3: Find the first (index) serum creatinine for each sepsis admission
    SELECT
        sa.hadm_id,
        le.valuenum AS admission_creatinine_value,
        ROW_NUMBER() OVER (PARTITION BY sa.hadm_id ORDER BY le.charttime ASC) as rn
    FROM
        SepsisAdmissions sa
    INNER JOIN
        `physionet-data.mimiciv_3_1_hosp.labevents` le
        ON sa.subject_id = le.subject_id AND sa.hadm_id = le.hadm_id
    WHERE
        le.itemid = 50912 -- itemid for 'Creatinine' (from d_labitems, commonly serum creatinine)
        AND le.valuenum IS NOT NULL -- Ensure a numeric value exists
)
-- Step 4: Calculate the maximum of these first creatinine values
SELECT
    MAX(fc.admission_creatinine_value) AS max_admission_serum_creatinine
FROM
    FirstCreatinine fc
WHERE
    fc.rn = 1; -- Select only the first creatinine measurement for each admission;