with DM and HF, report by class (Insulin vs Oral Agents) early (first 12h) and late (final 72h) rates (%) and early→late transitions.
-- This query first identifies a cohort of patients with both Diabetes and Heart Failure,
-- then analyzes their anti-diabetic medication patterns during the first 12 hours
-- and final 72 hours of their hospital stay.

WITH
-- Step 1: Find all hospital admissions with both Diabetes (DM) and Heart Failure (HF) diagnoses.
diagnoses AS (
    SELECT
        hadm_id
    FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd`
    GROUP BY
        hadm_id
    HAVING
        -- Patient must have at least one Diabetes Mellitus diagnosis
        (
            SUM(CASE WHEN icd_version = 9 AND SUBSTR(icd_code, 1, 3) = '250' THEN 1 ELSE 0 END) > 0 OR
            SUM(CASE WHEN icd_version = 10 AND SUBSTR(icd_code, 1, 3) IN ('E08', 'E09', 'E10', 'E11', 'E13') THEN 1 ELSE 0 END) > 0
        )
        AND
        -- Patient must have at least one Heart Failure diagnosis
        (
            SUM(CASE WHEN icd_version = 9 AND SUBSTR(icd_code, 1, 3) = '428' THEN 1 ELSE 0 END) > 0 OR
            SUM(CASE WHEN icd_version = 10 AND SUBSTR(icd_code, 1, 3) = 'I50' THEN 1 ELSE 0 END) > 0
        )
),

-- Step 2: Define the final patient cohort based on demographics and diagnoses.
-- We also ensure the hospital stay is long enough for the analysis.
cohort AS (
    SELECT
        p.subject_id,
        a.hadm_id,
        a.admittime,
        a.dischtime
    FROM
        `physionet-data.mimiciv_3_1_hosp.patients` AS p
    INNER JOIN
        `physionet-data.mimiciv_3_1_hosp.admissions` AS a
        ON p.subject_id = a.subject_id
    INNER JOIN
        diagnoses AS dx
        ON a.hadm_id = dx.hadm_id
    WHERE
        p.gender = 'F'
        AND p.anchor_age BETWEEN 86 AND 96
        -- Ensure admission is long enough for non-overlapping early (12h) and late (72h) windows
        AND DATETIME_DIFF(a.dischtime, a.admittime, HOUR) > (12 + 72)
),

-- Step 3: Classify anti-diabetic medications from the prescriptions table.
meds_classified AS (
    SELECT
        hadm_id,
        starttime,
        CASE
            WHEN LOWER(drug) LIKE '%insulin%' THEN 'Insulin'
            -- Oral Agents
            WHEN LOWER(drug) LIKE '%metformin%' THEN 'Oral Agent'
            WHEN LOWER(drug) LIKE '%glipizide%' THEN 'Oral Agent'
            WHEN LOWER(drug) LIKE '%glyburide%' THEN 'Oral Agent'
            WHEN LOWER(drug) LIKE '%glimepiride%' THEN 'Oral Agent'
            WHEN LOWER(drug) LIKE '%pioglitazone%' THEN 'Oral Agent'
            WHEN LOWER(drug) LIKE '%rosiglitazone%' THEN 'Oral Agent'
            WHEN LOWER(drug) LIKE '%acarbose%' THEN 'Oral Agent'
            WHEN LOWER(drug) LIKE '%miglitol%' THEN 'Oral Agent'
            WHEN LOWER(drug) LIKE '%sitagliptin%' THEN 'Oral Agent'
            WHEN LOWER(drug) LIKE '%saxagliptin%' THEN 'Oral Agent'
            WHEN LOWER(drug) LIKE '%linagliptin%' THEN 'Oral Agent'
            WHEN LOWER(drug) LIKE '%alogliptin%' THEN 'Oral Agent'
            WHEN LOWER(drug) LIKE '%canagliflozin%' THEN 'Oral Agent'
            WHEN LOWER(drug) LIKE '%dapagliflozin%' THEN 'Oral Agent'
            WHEN LOWER(drug) LIKE '%empagliflozin%' THEN 'Oral Agent'
            WHEN LOWER(drug) LIKE '%repaglinide%' THEN 'Oral Agent'
            WHEN LOWER(drug) LIKE '%nateglinide%' THEN 'Oral Agent'
            ELSE NULL
        END AS drug_class
    FROM
        `physionet-data.mimiciv_3_1_hosp.prescriptions`
    WHERE
        -- Exclude base solutions that might be mixed with insulin
        drug_type != 'BASE'
),

-- Step 4: For each patient in the cohort, flag whether they received Insulin or Oral Agents
-- in the early (first 12h) and late (final 72h) windows.
patient_med_periods AS (
    SELECT
        c.hadm_id,
        -- Early window flags (first 12 hours)
        MAX(CASE WHEN m.drug_class = 'Insulin' AND m.starttime >= c.admittime AND m.starttime < DATETIME_ADD(c.admittime, INTERVAL 12 HOUR) THEN 1 ELSE 0 END) AS got_insulin_early,
        MAX(CASE WHEN m.drug_class = 'Oral Agent' AND m.starttime >= c.admittime AND m.starttime < DATETIME_ADD(c.admittime, INTERVAL 12 HOUR) THEN 1 ELSE 0 END) AS got_oral_early,
        -- Late window flags (last 72 hours)
        MAX(CASE WHEN m.drug_class = 'Insulin' AND m.starttime > DATETIME_SUB(c.dischtime, INTERVAL 72 HOUR) AND m.starttime <= c.dischtime THEN 1 ELSE 0 END) AS got_insulin_late,
        MAX(CASE WHEN m.drug_class = 'Oral Agent' AND m.starttime > DATETIME_SUB(c.dischtime, INTERVAL 72 HOUR) AND m.starttime <= c.dischtime THEN 1 ELSE 0 END) AS got_oral_late
    FROM
        cohort AS c
    LEFT JOIN
        meds_classified AS m
        ON c.hadm_id = m.hadm_id
    GROUP BY
        c.hadm_id
),

-- Step 5: Consolidate flags into a single status ('Insulin', 'Oral Agent', 'Both', 'None') for each period.
patient_status AS (
    SELECT
        hadm_id,
        CASE
            WHEN got_insulin_early = 1 AND got_oral_early = 1 THEN 'Both'
            WHEN got_insulin_early = 1 THEN 'Insulin'
            WHEN got_oral_early = 1 THEN 'Oral Agent'
            ELSE 'None'
        END AS early_status,
        CASE
            WHEN got_insulin_late = 1 AND got_oral_late = 1 THEN 'Both'
            WHEN got_insulin_late = 1 THEN 'Insulin'
            WHEN got_oral_late = 1 THEN 'Oral Agent'
            ELSE 'None'
        END AS late_status
    FROM
        patient_med_periods
),

-- Step 6: Perform the final calculations for rates and transitions.
cohort_count AS (
    SELECT COUNT(hadm_id) AS total_patients FROM cohort
),
rates_calc AS (
    SELECT
        'Insulin' AS drug_class,
        ROUND(SUM(got_insulin_early) * 100.0 / (SELECT total_patients FROM cohort_count), 1) AS early_rate_pct,
        ROUND(SUM(got_insulin_late) * 100.0 / (SELECT total_patients FROM cohort_count), 1) AS late_rate_pct
    FROM patient_med_periods
    UNION ALL
    SELECT
        'Oral Agent' AS drug_class,
        ROUND(SUM(got_oral_early) * 100.0 / (SELECT total_patients FROM cohort_count), 1) AS early_rate_pct,
        ROUND(SUM(got_oral_late) * 100.0 / (SELECT total_patients FROM cohort_count), 1) AS late_rate_pct
    FROM patient_med_periods
),
transitions_calc AS (
    SELECT
        early_status,
        late_status,
        COUNT(hadm_id) AS num_patients,
        ROUND(COUNT(hadm_id) * 100.0 / (SELECT total_patients FROM cohort_count), 1) AS pct_of_cohort
    FROM patient_status
    GROUP BY
        early_status,
        late_status
)

-- Step 7: Combine the results into a single, user-friendly table.
-- Part 1: Rates by Class
SELECT
    'Rates by Class' AS analysis_type,
    drug_class AS category,
    CAST(early_rate_pct AS STRING) AS value1,
    CAST(late_rate_pct AS STRING) AS value2,
    'Early (first 12h) %' AS value1_description,
    'Late (final 72h) %' AS value2_description
FROM rates_calc

UNION ALL

-- Part 2: Transitions
SELECT
    'Early to Late Transitions' AS analysis_type,
    CONCAT(early_status, ' -> ', late_status) AS category,
    CAST(num_patients AS STRING) AS value1,
    CAST(pct_of_cohort AS STRING) AS value2,
    'Number of Patients' AS value1_description,
    'Percent of Cohort' AS value2_description
FROM transitions_calc
ORDER BY
    analysis_type DESC, category;