WITH PatientCohort AS (
    -- Step 1: Identify hospital admissions for male patients aged 35-45
    -- with a diagnosis of AMI or chest pain.
    SELECT DISTINCT adm.hadm_id
    FROM `physionet-data.mimiciv_3_1_hosp.admissions` AS adm
    INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` AS pat
        ON adm.subject_id = pat.subject_id
    INNER JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` AS dx
        ON adm.hadm_id = dx.hadm_id
    INNER JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` AS d_dx
        ON dx.icd_code = d_dx.icd_code AND dx.icd_version = d_dx.icd_version
    WHERE
        -- Filter for male patients
        pat.gender = 'M'
        -- Calculate and filter for age at admission between 35 and 45
        AND (
            pat.anchor_age + EXTRACT(YEAR FROM adm.admittime) - pat.anchor_year
        ) BETWEEN 35 AND 45
        -- Filter for AMI (ICD-9 and ICD-10) or chest pain diagnoses
        AND (
            dx.icd_code LIKE '410%'  -- ICD-9 Acute Myocardial Infarction
            OR dx.icd_code LIKE 'I21%' -- ICD-10 Acute Myocardial Infarction
            OR LOWER(d_dx.long_title) LIKE '%chest pain%'
        )
),
FirstTroponin AS (
    -- Step 2: Find the first high-sensitivity troponin T result for each admission
    -- The ROW_NUMBER identifies the first test based on the earliest charttime
    SELECT
        hadm_id,
        valuenum,
        ROW_NUMBER() OVER(PARTITION BY hadm_id ORDER BY charttime ASC) as rn
    FROM `physionet-data.mimiciv_3_1_hosp.labevents`
    WHERE
        itemid = 52598 -- d_labitems: Troponin T, High Sensitivity
        AND valuenum IS NOT NULL -- Ensure the value is a number for comparison
)
-- Step 3: Join the patient cohort with their first troponin, categorize the value, and count
SELECT
    CASE
        WHEN ft.valuenum < 14 THEN 'Normal'
        WHEN ft.valuenum BETWEEN 14 AND 52 THEN 'Borderline'
        WHEN ft.valuenum > 52 THEN 'Myocardial Injury'
        ELSE 'Error/Unknown'
    END AS troponin_category,
    COUNT(*) AS number_of_patients
FROM FirstTroponin AS ft
INNER JOIN PatientCohort AS pc
    ON ft.hadm_id = pc.hadm_id
WHERE
    ft.rn = 1 -- Only consider the first measurement for each admission
GROUP BY
    troponin_category
ORDER BY
    -- Custom order for a logical presentation of categories
    CASE
        WHEN troponin_category = 'Normal' THEN 1
        WHEN troponin_category = 'Borderline' THEN 2
        WHEN troponin_category = 'Myocardial Injury' THEN 3
        ELSE 4
    END;