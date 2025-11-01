WITH
-- Step 1: Define the patient cohort of female inpatients aged 51-61
cohort AS (
    SELECT
        p.subject_id,
        a.hadm_id,
        a.admittime,
        a.dischtime,
        DATETIME_ADD(a.admittime, INTERVAL 48 HOUR) AS first_48h_end,
        DATETIME_SUB(a.dischtime, INTERVAL 24 HOUR) AS final_24h_start
    FROM
        `physionet-data.mimiciv_3_1_hosp.patients` AS p
    INNER JOIN
        `physionet-data.mimiciv_3_1_hosp.admissions` AS a
            ON p.subject_id = a.subject_id
    WHERE
        p.gender = 'F'
        AND p.anchor_age BETWEEN 51 AND 61
),

-- Step 2: Identify relevant medication prescriptions for the cohort and categorize them
meds AS (
    SELECT
        pr.hadm_id,
        pr.starttime,
        -- Assume prescriptions with no stoptime continue until discharge
        COALESCE(pr.stoptime, co.dischtime) AS stoptime,
        CASE
            WHEN LOWER(pr.drug) LIKE '%insulin%' THEN 'Insulin'
            WHEN REGEXP_CONTAINS(LOWER(pr.drug), 'metformin|glipizide|glyburide|pioglitazone|rosiglitazone|sitagliptin|januvia|glimepiride|repaglinide|acarbose|saxagliptin|linagliptin|canagliflozin|dapagliflozin|empagliflozin') THEN 'Oral'
            ELSE NULL
        END AS med_category
    FROM
        `physionet-data.mimiciv_3_1_hosp.prescriptions` AS pr
    INNER JOIN
        cohort AS co ON pr.hadm_id = co.hadm_id
    WHERE
        -- Pre-filter for performance
        LOWER(pr.drug) LIKE '%insulin%'
        OR REGEXP_CONTAINS(LOWER(pr.drug), 'metformin|glipizide|glyburide|pioglitazone|rosiglitazone|sitagliptin|januvia|glimepiride|repaglinide|acarbose|saxagliptin|linagliptin|canagliflozin|dapagliflozin|empagliflozin')
),

-- Step 3: For each patient and medication type, flag if it was administered in each window
patient_med_periods AS (
    SELECT
        co.hadm_id,
        m.med_category,
        -- Flag is 1 if any prescription of this type was active in the first 48 hours
        MAX(CASE
            WHEN m.starttime <= co.first_48h_end AND m.stoptime >= co.admittime THEN 1
            ELSE 0
        END) AS in_first_48h,
        -- Flag is 1 if any prescription of this type was active in the final 24 hours
        MAX(CASE
            WHEN m.starttime <= co.dischtime AND m.stoptime >= co.final_24h_start THEN 1
            ELSE 0
        END) AS in_final_24h
    FROM
        cohort AS co
    LEFT JOIN
        meds AS m ON co.hadm_id = m.hadm_id
    WHERE m.med_category IS NOT NULL
    GROUP BY
        co.hadm_id, m.med_category
),

-- Step 4: Pivot the data to get one row per patient with flags for both medication types
patient_summary AS (
    SELECT
        co.hadm_id,
        MAX(CASE WHEN pmp.med_category = 'Insulin' THEN pmp.in_first_48h ELSE 0 END) AS insulin_first_48h,
        MAX(CASE WHEN pmp.med_category = 'Insulin' THEN pmp.in_final_24h ELSE 0 END) AS insulin_final_24h,
        MAX(CASE WHEN pmp.med_category = 'Oral' THEN pmp.in_first_48h ELSE 0 END) AS oral_first_48h,
        MAX(CASE WHEN pmp.med_category = 'Oral' THEN pmp.in_final_24h ELSE 0 END) AS oral_final_24h
    FROM
        cohort AS co
    LEFT JOIN
        patient_med_periods AS pmp ON co.hadm_id = pmp.hadm_id
    GROUP BY
        co.hadm_id
)

-- Step 5: Final aggregation to calculate percentages and counts for each medication category
SELECT
    'Insulin' AS med_category,
    ROUND(100 * SAFE_DIVIDE(SUM(insulin_first_48h), COUNT(hadm_id)), 2) AS percent_on_in_first_48h,
    ROUND(100 * SAFE_DIVIDE(SUM(insulin_final_24h), COUNT(hadm_id)), 2) AS percent_on_in_final_24h,
    SUM(CASE WHEN insulin_first_48h = 1 AND insulin_final_24h = 1 THEN 1 ELSE 0 END) AS continued_count,
    SUM(CASE WHEN insulin_first_48h = 0 AND insulin_final_24h = 1 THEN 1 ELSE 0 END) AS initiated_count,
    SUM(CASE WHEN insulin_first_48h = 1 AND insulin_final_24h = 0 THEN 1 ELSE 0 END) AS discontinued_count,
    COUNT(hadm_id) AS total_patients_in_cohort
FROM
    patient_summary

UNION ALL

SELECT
    'Oral Agents' AS med_category,
    ROUND(100 * SAFE_DIVIDE(SUM(oral_first_48h), COUNT(hadm_id)), 2) AS percent_on_in_first_48h,
    ROUND(100 * SAFE_DIVIDE(SUM(oral_final_24h), COUNT(hadm_id)), 2) AS percent_on_in_final_24h,
    SUM(CASE WHEN oral_first_48h = 1 AND oral_final_24h = 1 THEN 1 ELSE 0 END) AS continued_count,
    SUM(CASE WHEN oral_first_48h = 0 AND oral_final_24h = 1 THEN 1 ELSE 0 END) AS initiated_count,
    SUM(CASE WHEN oral_first_48h = 1 AND oral_final_24h = 0 THEN 1 ELSE 0 END) AS discontinued_count,
    COUNT(hadm_id) AS total_patients_in_cohort
FROM
    patient_summary;