WITH
-- Step 1: Identify hospital admissions for Acute Coronary Syndrome (ACS)
-- This includes codes for Acute Myocardial Infarction and Unstable Angina
acs_admissions AS (
    SELECT DISTINCT hadm_id
    FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd`
    WHERE
        (icd_version = 9 AND (SUBSTR(icd_code, 1, 3) = '410' OR icd_code = '4111'))
        OR
        (icd_version = 10 AND (SUBSTR(icd_code, 1, 3) = 'I21' OR icd_code = 'I200'))
),

-- Step 2: Filter for the target patient cohort: males aged 79-89 with an ACS admission
target_cohort AS (
    SELECT
        adm.hadm_id
    FROM `physionet-data.mimiciv_3_1_hosp.admissions` AS adm
    INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` AS pat
        ON adm.subject_id = pat.subject_id
    INNER JOIN acs_admissions
        ON adm.hadm_id = acs_admissions.hadm_id
    WHERE
        pat.gender = 'M'
        -- Calculate age at admission
        AND (EXTRACT(YEAR FROM adm.admittime) - pat.anchor_year + pat.anchor_age) BETWEEN 79 AND 89
),

-- Step 3: Find the first (index) Troponin T measurement for each admission in the cohort
first_troponin AS (
    SELECT
        hadm_id,
        valuenum
    FROM (
        SELECT
            lab.hadm_id,
            lab.valuenum,
            -- Rank troponin results by time to find the first one per admission
            ROW_NUMBER() OVER(PARTITION BY lab.hadm_id ORDER BY lab.charttime ASC) AS rn
        FROM `physionet-data.mimiciv_3_1_hosp.labevents` AS lab
        INNER JOIN target_cohort
            ON lab.hadm_id = target_cohort.hadm_id
        WHERE
            lab.itemid = 51003 -- 51003 is the itemid for 'Troponin T'
            AND lab.valuenum IS NOT NULL -- Ensure the value is numeric for comparison
    ) AS ranked_labs
    WHERE rn = 1 -- Filter for only the first measurement
)

-- Step 4: Categorize the index troponin values and count the admissions in each category
SELECT
    CASE
        WHEN valuenum <= 0.04 THEN 'Normal (<=0.04 ng/mL)'
        WHEN valuenum > 0.04 AND valuenum <= 0.1 THEN 'Borderline (>0.04-0.1 ng/mL)'
        WHEN valuenum > 0.1 THEN 'Elevated (>0.1 ng/mL)'
    END AS troponin_category,
    COUNT(hadm_id) AS admission_count
FROM first_troponin
GROUP BY troponin_category
-- Order the results logically from normal to elevated
ORDER BY MIN(valuenum);