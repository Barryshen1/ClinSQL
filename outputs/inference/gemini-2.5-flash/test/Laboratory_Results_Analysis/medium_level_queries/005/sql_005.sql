WITH admission_cohort AS (
    -- Step 1: Identify male patients aged 35-45 admitted with Chest Pain or AMI.
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
        ON adm.hadm_id = diag.hadm_id
    WHERE
        pat.gender = 'M'
        AND pat.anchor_age BETWEEN 35 AND 45 -- Age at admission between 35 and 45 years
        AND (
            diag.icd_code LIKE 'R07%' -- ICD-10 codes for Chest Pain (e.g., R07.1, R07.2, R07.3, R07.4)
            OR diag.icd_code LIKE 'I21%' -- ICD-10 codes for Acute Myocardial Infarction (AMI)
        )
),
troponin_events AS (
    -- Step 2: Find all high-sensitivity Troponin T lab events for the identified cohort
    SELECT
        ac.subject_id,
        ac.hadm_id,
        le.charttime,
        le.valuenum
    FROM
        admission_cohort AS ac
    INNER JOIN
        `physionet-data.mimiciv_3_1_hosp.labevents` AS le
        ON ac.subject_id = le.subject_id AND ac.hadm_id = le.hadm_id
    INNER JOIN
        `physionet-data.mimiciv_3_1_hosp.d_labitems` AS dli
        ON le.itemid = dli.itemid
    WHERE
        dli.itemid = 51003 -- ItemID for 'Troponin T, High Sensitive'
        AND le.valuenum IS NOT NULL -- Exclude records without a numeric value
        AND le.valuenum >= 0 -- Ensure positive troponin values
),
first_troponin_per_admission AS (
    -- Step 3: Get the first high-sensitivity Troponin T result for each admission
    SELECT
        subject_id,
        hadm_id,
        valuenum,
        ROW_NUMBER() OVER (PARTITION BY subject_id, hadm_id ORDER BY charttime ASC) AS rn
    FROM
        troponin_events
)
-- Step 4 & 5: Categorize and count the first troponin T results
SELECT
    CASE
        WHEN ft.valuenum < 14 THEN 'Normal (<14 ng/L)'
        WHEN ft.valuenum >= 14 AND ft.valuenum <= 52 THEN 'Borderline (14-52 ng/L)'
        WHEN ft.valuenum > 52 THEN 'Myocardial Injury (>52 ng/L)'
        ELSE 'Uncategorized (Missing or invalid value)' -- Should not be hit if filters are effective
    END AS troponin_category,
    COUNT(DISTINCT ft.hadm_id) AS num_admissions
FROM
    first_troponin_per_admission AS ft
WHERE
    ft.rn = 1 -- Select only the first recorded troponin T result for each admission
GROUP BY
    troponin_category
ORDER BY
    troponin_category;