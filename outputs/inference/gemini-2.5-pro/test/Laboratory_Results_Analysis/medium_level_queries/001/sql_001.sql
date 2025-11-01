WITH ami_patients AS (
    -- Step 1: Identify female patients aged 40-50 admitted with an AMI diagnosis
    SELECT DISTINCT adm.hadm_id
    FROM `physionet-data.mimiciv_3_1_hosp.admissions` AS adm
    INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` AS pat
        ON adm.subject_id = pat.subject_id
    INNER JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` AS dx
        ON adm.hadm_id = dx.hadm_id
    WHERE
        pat.gender = 'F'
        AND (EXTRACT(YEAR FROM adm.admittime) - pat.anchor_year) + pat.anchor_age BETWEEN 40 AND 50
        AND (
            dx.icd_code LIKE '410%' -- ICD-9 for AMI
            OR dx.icd_code LIKE 'I21%' -- ICD-10 for first AMI
            OR dx.icd_code LIKE 'I22%' -- ICD-10 for subsequent AMI
        )
),
first_troponin AS (
    -- Step 2: Find the first Troponin T measurement for each of these admissions
    SELECT
        le.hadm_id,
        le.valuenum,
        ROW_NUMBER() OVER(PARTITION BY le.hadm_id ORDER BY le.charttime) as rn
    FROM `physionet-data.mimiciv_3_1_hosp.labevents` AS le
    INNER JOIN ami_patients
        ON le.hadm_id = ami_patients.hadm_id
    WHERE
        le.itemid = 50912 -- Troponin T
        AND le.valuenum IS NOT NULL -- Exclude results without a numeric value
)
-- Step 3: Categorize the first Troponin T value and count the number of patients in each category
SELECT
    CASE
        WHEN ft.valuenum < 0.01 THEN 'Normal'
        WHEN ft.valuenum BETWEEN 0.01 AND 0.04 THEN 'Borderline'
        WHEN ft.valuenum > 0.04 THEN 'Elevated'
    END AS troponin_category,
    COUNT(*) AS number_of_patients
FROM first_troponin AS ft
WHERE
    ft.rn = 1 -- Filter to only the first measurement per admission
GROUP BY
    troponin_category
ORDER BY
    troponin_category;