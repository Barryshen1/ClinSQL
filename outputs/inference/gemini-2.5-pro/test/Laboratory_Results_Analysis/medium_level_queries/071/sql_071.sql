WITH acs_admissions AS (
    SELECT DISTINCT hadm_id
    FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd`
    WHERE
        -- ICD-9 codes for ACS and related conditions
        (icd_version = 9 AND (
            SUBSTR(icd_code, 1, 3) = '410'      -- Acute Myocardial Infarction
            OR SUBSTR(icd_code, 1, 5) = '411.1' -- Intermediate coronary syndrome (Unstable Angina)
        ))
        -- ICD-10 codes for ACS and related conditions
        OR (icd_version = 10 AND (
            SUBSTR(icd_code, 1, 3) = 'I21'      -- Acute Myocardial Infarction
            OR SUBSTR(icd_code, 1, 4) = 'I20.0'    -- Unstable Angina
            OR SUBSTR(icd_code, 1, 4) = 'I24.0'    -- Coronary thrombosis not resulting in myocardial infarction
        ))
),

-- Step 2: Identify the primary cohort of female patients aged 43-53 with an ACS-related admission
cohort AS (
    SELECT
        pat.subject_id,
        adm.hadm_id,
        DATETIME_DIFF(adm.dischtime, adm.admittime, HOUR) / 24.0 AS los_days
    FROM `physionet-data.mimiciv_3_1_hosp.patients` AS pat
    INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` AS adm
        ON pat.subject_id = adm.subject_id
    INNER JOIN acs_admissions AS acs
        ON adm.hadm_id = acs.hadm_id
    WHERE
        pat.gender = 'F'
        AND pat.anchor_age BETWEEN 43 AND 53
),

-- Step 3: Find the first Troponin T measurement for each admission in the cohort
first_troponin AS (
    SELECT
        lab.hadm_id,
        lab.valuenum,
        -- Assign a rank to each troponin test for a given admission, ordered by time
        ROW_NUMBER() OVER(PARTITION BY lab.hadm_id ORDER BY lab.charttime) AS rn
    FROM `physionet-data.mimiciv_3_1_hosp.labevents` AS lab
    -- Ensure we only look at lab events for admissions in our cohort
    INNER JOIN cohort ON lab.hadm_id = cohort.hadm_id
    WHERE
        lab.itemid = 51003 -- Troponin T
        AND lab.valuenum IS NOT NULL -- Exclude non-numeric or missing results
),

-- Step 4: Join cohort with their categorized first Troponin T measurement
categorized_patients AS (
    SELECT
        c.hadm_id,
        c.los_days,
        -- Categorize based on common clinical thresholds for high-sensitivity Troponin T (ng/mL)
        -- The 0.01 cutoff is based on the ref_range_upper in labevents for this itemid
        CASE
            WHEN ft.valuenum <= 0.01 THEN 'Normal'
            WHEN ft.valuenum > 0.01 AND ft.valuenum <= 0.04 THEN 'Borderline'
            WHEN ft.valuenum > 0.04 THEN 'Elevated'
            ELSE NULL
        END AS troponin_category
    FROM cohort AS c
    INNER JOIN first_troponin AS ft
        ON c.hadm_id = ft.hadm_id
    WHERE
        ft.rn = 1 -- Filter for only the first measurement
)

-- Final step: Aggregate the results to get counts, percentages, and average LOS
SELECT
    cp.troponin_category,
    COUNT(cp.hadm_id) AS patient_count,
    -- Calculate percentage relative to the total number of patients with a troponin test
    ROUND(SAFE_DIVIDE(COUNT(cp.hadm_id) * 100.0, SUM(COUNT(cp.hadm_id)) OVER()), 2) AS percentage_of_patients,
    ROUND(AVG(cp.los_days), 2) AS avg_hospital_los_days
FROM categorized_patients AS cp
WHERE cp.troponin_category IS NOT NULL -- Exclude any patient who didn't fall into a category
GROUP BY cp.troponin_category
-- Order by a logical clinical progression for better readability
ORDER BY
    CASE
        WHEN cp.troponin_category = 'Normal' THEN 1
        WHEN cp.troponin_category = 'Borderline' THEN 2
        WHEN cp.troponin_category = 'Elevated' THEN 3
    END;