WITH
-- Step 1: Identify hospital admissions for female patients, aged 46-56, with an ACS diagnosis.
acs_hadm_ids AS (
    SELECT DISTINCT adm.hadm_id
    FROM `physionet-data.mimiciv_3_1_hosp.admissions` AS adm
    JOIN `physionet-data.mimiciv_3_1_hosp.patients` AS pat
        ON adm.subject_id = pat.subject_id
    JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` AS dx
        ON adm.hadm_id = dx.hadm_id
    WHERE
        pat.gender = 'F'
        -- Calculate age at admission and filter for the specified range
        AND (DATETIME_DIFF(adm.admittime, DATETIME(pat.anchor_year, 1, 1, 0, 0, 0), YEAR) + pat.anchor_age) BETWEEN 46 AND 56
        -- Filter for ICD codes related to Acute Coronary Syndrome (ACS)
        AND (
            (dx.icd_version = 9 AND (dx.icd_code LIKE '410%' OR dx.icd_code = '4111')) -- Acute MI, Unstable Angina
            OR (dx.icd_version = 10 AND (dx.icd_code LIKE 'I21%' OR dx.icd_code LIKE 'I22%' OR dx.icd_code = 'I200')) -- Acute MI, Unstable Angina
        )
),

-- Step 2: For the above cohort, find the first high-sensitivity Troponin T result.
first_hstnt AS (
    SELECT
        hadm_id,
        valuenum,
        -- Rank troponin results by time to find the first one
        ROW_NUMBER() OVER(PARTITION BY hadm_id ORDER BY charttime ASC) as rn
    FROM `physionet-data.mimiciv_3_1_hosp.labevents`
    WHERE
        itemid = 52598 -- itemid for 'Troponin T, High Sensitivity'
        AND valuenum IS NOT NULL
        -- Only consider admissions from our ACS cohort
        AND hadm_id IN (SELECT hadm_id FROM acs_hadm_ids)
),

-- Step 3: Combine admission data with the first troponin, categorize it, and calculate LOS.
categorized_admissions AS (
    SELECT
        adm.hadm_id,
        -- Categorize the first troponin value based on clinical cutoffs
        CASE
            WHEN tnt.valuenum < 14 THEN 'Normal'
            WHEN tnt.valuenum BETWEEN 14 AND 52 THEN 'Borderline'
            WHEN tnt.valuenum > 52 THEN 'Myocardial Injury'
        END AS troponin_category,
        -- Calculate hospital length of stay in fractional days
        TIMESTAMP_DIFF(adm.dischtime, adm.admittime, HOUR) / 24.0 AS hospital_los_days
    FROM `physionet-data.mimiciv_3_1_hosp.admissions` AS adm
    -- Join to get only admissions that have a first hs-TnT result from our cohort
    JOIN first_hstnt AS tnt
        ON adm.hadm_id = tnt.hadm_id
    WHERE
        tnt.rn = 1 -- Ensure we only use the first measurement
)

-- Step 4: Aggregate the results to get counts, percentages, and mean LOS for each category.
SELECT
    troponin_category,
    COUNT(hadm_id) AS admission_count,
    ROUND(COUNT(hadm_id) * 100.0 / SUM(COUNT(hadm_id)) OVER(), 1) AS percentage_of_admissions,
    ROUND(AVG(hospital_los_days), 2) AS mean_hospital_los_days
FROM categorized_admissions
GROUP BY
    troponin_category
ORDER BY
    -- Order the results logically by severity
    CASE
        WHEN troponin_category = 'Normal' THEN 1
        WHEN troponin_category = 'Borderline' THEN 2
        WHEN troponin_category = 'Myocardial Injury' THEN 3
    END;