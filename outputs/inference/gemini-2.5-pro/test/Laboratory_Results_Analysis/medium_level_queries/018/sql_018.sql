WITH
-- 1. Identify all hospital admissions related to Acute Coronary Syndrome (ACS)
acs_admissions AS (
    SELECT DISTINCT hadm_id
    FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd`
    WHERE
    -- ICD-9 codes for ACS
    (icd_version = 9 AND (
        SUBSTR(icd_code, 1, 3) = '410' -- Acute Myocardial Infarction
        OR SUBSTR(icd_code, 1, 3) = '411'    -- Other acute and subacute forms of ischemic heart disease
    )) OR
    -- ICD-10 codes for ACS
    (icd_version = 10 AND (
        SUBSTR(icd_code, 1, 3) = 'I21' -- Acute Myocardial Infarction
        OR SUBSTR(icd_code, 1, 3) = 'I22' -- Subsequent ST elevation (STEMI) and non-ST elevation (NSTEMI) myocardial infarction
        OR icd_code = 'I20.0'             -- Unstable angina
    ))
),

-- 2. Filter for the specific patient cohort: males aged 90-100
--    and calculate their hospital length of stay
patient_cohort AS (
    SELECT
        p.subject_id,
        a.hadm_id,
        -- Calculate length of stay in days
        DATETIME_DIFF(a.dischtime, a.admittime, DAY) AS los_days
    FROM `physionet-data.mimiciv_3_1_hosp.patients` AS p
    INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` AS a
        ON p.subject_id = a.subject_id
    INNER JOIN acs_admissions AS acs
        ON a.hadm_id = acs.hadm_id
    WHERE
        p.gender = 'M'
        AND p.anchor_age BETWEEN 90 AND 100
),

-- 3. Find the first (index) Troponin T measurement for each admission in the cohort
index_troponin AS (
    SELECT
        pc.hadm_id,
        pc.los_days,
        le.valuenum,
        -- Use a window function to rank Troponin T tests by time for each admission
        ROW_NUMBER() OVER(PARTITION BY pc.hadm_id ORDER BY le.charttime) AS rn
    FROM patient_cohort AS pc
    INNER JOIN `physionet-data.mimiciv_3_1_hosp.labevents` AS le
        ON pc.hadm_id = le.hadm_id
    WHERE
        le.itemid = 51003 -- d_labitems.label = 'Troponin T'
        AND le.valuenum IS NOT NULL -- Exclude rows without a numeric value
),

-- 4. Categorize the index Troponin T values from the first measurement
categorized_troponin AS (
    SELECT
        hadm_id,
        los_days,
        valuenum,
        CASE
            WHEN valuenum < 0.01 THEN 'Normal'
            WHEN valuenum >= 0.01 AND valuenum <= 0.04 THEN 'Borderline'
            WHEN valuenum > 0.04 THEN 'Elevated'
            ELSE 'Uncategorized'
        END AS troponin_category
    FROM index_troponin
    WHERE rn = 1 -- Select only the first measurement
)

-- 5. Aggregate the results to get counts, percentages, and mean LOS per category
SELECT
    ct.troponin_category,
    COUNT(ct.hadm_id) AS patient_count,
    ROUND(100.0 * COUNT(ct.hadm_id) / SUM(COUNT(ct.hadm_id)) OVER(), 2) AS percentage_of_patients,
    ROUND(AVG(ct.los_days), 2) AS mean_los_days
FROM categorized_troponin AS ct
GROUP BY ct.troponin_category
ORDER BY
    CASE
        WHEN ct.troponin_category = 'Normal' THEN 1
        WHEN ct.troponin_category = 'Borderline' THEN 2
        WHEN ct.troponin_category = 'Elevated' THEN 3
        ELSE 4
    END;