WITH
    -- 1. Identify patients admitted with suspected ACS within the specified age group and gender
    suspected_acs AS (
        SELECT DISTINCT
            adm.subject_id,
            adm.hadm_id,
            adm.admittime
        FROM
            `physionet-data.mimiciv_3_1_hosp.admissions` AS adm
            INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` AS pat
                ON adm.subject_id = pat.subject_id
            INNER JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` AS diag
                ON adm.subject_id = diag.subject_id AND adm.hadm_id = diag.hadm_id
        WHERE
            pat.gender = 'M'
            AND pat.anchor_age BETWEEN 79 AND 89
            AND diag.icd_version = 10 -- Focus on ICD-10 for MIMIC-IV
            AND (
                diag.icd_code LIKE 'I20.0%' -- Unstable angina
                OR diag.icd_code LIKE 'I21.%' -- Acute myocardial infarction (e.g., STEMI, NSTEMI)
                OR diag.icd_code LIKE 'I22.%' -- Subsequent myocardial infarction
                OR diag.icd_code LIKE 'I24.%' -- Other acute ischemic heart diseases
            )
    ),
    -- 2. Extract all Troponin T lab events for the identified admissions
    raw_troponin_t AS (
        SELECT
            sa.subject_id,
            sa.hadm_id,
            le.charttime,
            le.valuenum
        FROM
            `physionet-data.mimiciv_3_1_hosp.labevents` AS le
            INNER JOIN `physionet-data.mimiciv_3_1_hosp.d_labitems` AS dil
                ON le.itemid = dil.itemid
            INNER JOIN suspected_acs AS sa
                ON le.subject_id = sa.subject_id AND le.hadm_id = sa.hadm_id
        WHERE
            LOWER(dil.label) LIKE '%troponin t%' -- Find Troponin T lab tests
            AND le.valuenum IS NOT NULL -- Ensure a numeric result exists
            AND le.valuenum >= 0 -- Ensure non-negative value
            AND le.charttime >= sa.admittime -- Ensure lab is taken during or after admission
    ),
    -- 3. Get the initial (earliest) Troponin T value for each admission
    initial_troponin_t AS (
        SELECT
            subject_id,
            hadm_id,
            charttime,
            valuenum AS initial_troponin_t_value,
            ROW_NUMBER() OVER (PARTITION BY subject_id, hadm_id ORDER BY charttime) AS rn
        FROM
            raw_troponin_t
    ),
    -- 4. Categorize initial Troponin T values
    categorized_troponin_t AS (
        SELECT
            subject_id,
            hadm_id,
            initial_troponin_t_value,
            CASE
                WHEN initial_troponin_t_value < 0.01 THEN 'Normal (< 0.01 ng/mL)'
                WHEN initial_troponin_t_value >= 0.01 AND initial_troponin_t_value <= 0.03 THEN 'Borderline (0.01 - 0.03 ng/mL)'
                WHEN initial_troponin_t_value > 0.03 THEN 'Elevated (> 0.03 ng/mL)'
                ELSE 'Unknown'
            END AS troponin_category
        FROM
            initial_troponin_t
        WHERE
            rn = 1 -- Select only the earliest measurement
    )
-- 5. Calculate counts, percentages, and descriptive statistics by category
SELECT
    troponin_category,
    COUNT(hadm_id) AS patient_count,
    COUNT(hadm_id) * 100.0 / SUM(COUNT(hadm_id)) OVER () AS percentage,
    ROUND(AVG(initial_troponin_t_value), 4) AS mean_troponin_t_value,
    ROUND(APPROX_QUANTILES(initial_troponin_t_value, 4)[OFFSET(2)], 4) AS median_troponin_t_value,
    ROUND(APPROX_QUANTILES(initial_troponin_t_value, 4)[OFFSET(1)], 4) AS q1_troponin_t_value,
    ROUND(APPROX_QUANTILES(initial_troponin_t_value, 4)[OFFSET(3)], 4) AS q3_troponin_t_value
FROM
    categorized_troponin_t
GROUP BY
    troponin_category
ORDER BY
    CASE troponin_category
        WHEN 'Normal (< 0.01 ng/mL)' THEN 1
        WHEN 'Borderline (0.01 - 0.03 ng/mL)' THEN 2
        WHEN 'Elevated (> 0.03 ng/mL)' THEN 3
        ELSE 4
    END;