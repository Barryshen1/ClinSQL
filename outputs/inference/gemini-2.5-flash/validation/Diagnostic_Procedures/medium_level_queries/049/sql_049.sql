WITH admissions_filtered_cohort AS (
    SELECT
        ad.subject_id,
        ad.hadm_id,
        DATETIME_DIFF(ad.dischtime, ad.admittime, DAY) AS los_days
    FROM
        `physionet-data.mimiciv_3_1_hosp.admissions` AS ad
    JOIN
        `physionet-data.mimiciv_3_1_hosp.patients` AS p
        ON ad.subject_id = p.subject_id
    WHERE
        p.gender = 'M'
        AND p.anchor_age BETWEEN 87 AND 97
        AND ad.dischtime IS NOT NULL -- Ensure admission is complete
        AND DATETIME_DIFF(ad.dischtime, ad.admittime, DAY) BETWEEN 1 AND 7 -- Pre-filter for relevant LOS
),
sepsis_hadm AS (
    -- Identify admissions with any sepsis-related ICD code
    SELECT DISTINCT hadm_id
    FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd`
    WHERE
        (
            icd_version = 9 AND (icd_code LIKE '038%' OR icd_code IN ('99591', '99592'))
            OR icd_version = 10 AND (icd_code LIKE 'A40%' OR icd_code LIKE 'A41%' OR icd_code = 'R6520')
        )
),
shock_hadm AS (
    -- Identify admissions with any septic shock-related ICD code
    SELECT DISTINCT hadm_id
    FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd`
    WHERE
        (
            icd_version = 9 AND icd_code = '78552'
            OR icd_version = 10 AND icd_code = 'R6521'
        )
),
qualified_admissions AS (
    -- Select admissions that meet age, gender, LOS, and "sepsis without shock" criteria
    SELECT
        afc.subject_id,
        afc.hadm_id,
        afc.los_days
    FROM
        admissions_filtered_cohort AS afc
    WHERE
        afc.hadm_id IN (SELECT hadm_id FROM sepsis_hadm)
        AND afc.hadm_id NOT IN (SELECT hadm_id FROM shock_hadm)
),
admissions_with_procedure_counts AS (
    -- Count diagnostic procedures for each qualified admission
    SELECT
        qa.hadm_id,
        qa.los_days,
        COUNT(pi.icd_code) AS num_procedures -- Count all procedures for the admission, 0 if no procedures
    FROM
        qualified_admissions AS qa
    LEFT JOIN -- Use LEFT JOIN to include admissions with 0 procedures
        `physionet-data.mimiciv_3_1_hosp.procedures_icd` AS pi
        ON qa.subject_id = pi.subject_id AND qa.hadm_id = pi.hadm_id
    GROUP BY
        qa.hadm_id, qa.los_days
)
-- Final aggregation to calculate mean procedures by LOS category
SELECT
    CASE
        WHEN awpc.los_days BETWEEN 1 AND 3 THEN '1-3 days'
        WHEN awpc.los_days BETWEEN 4 AND 7 THEN '4-7 days'
        ELSE 'Other' -- Should not be reached given initial LOS filter, but good practice
    END AS los_category,
    AVG(awpc.num_procedures) AS mean_diagnostic_procedures
FROM
    admissions_with_procedure_counts AS awpc
GROUP BY
    los_category
ORDER BY
    los_category;