WITH
-- CTE 1: Find all hospital admissions with diagnoses for both T2DM and Heart Failure
hadm_with_diagnoses AS (
    SELECT hadm_id FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd`
    WHERE
        (icd_version = 9 AND SUBSTR(icd_code, 1, 3) = '250') OR -- T2DM ICD-9
        (icd_version = 10 AND SUBSTR(icd_code, 1, 3) = 'E11')    -- T2DM ICD-10
    GROUP BY hadm_id
    INTERSECT DISTINCT
    SELECT hadm_id FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd`
    WHERE
        (icd_version = 9 AND SUBSTR(icd_code, 1, 3) = '428') OR -- HF ICD-9
        (icd_version = 10 AND SUBSTR(icd_code, 1, 3) = 'I50')    -- HF ICD-10
    GROUP BY hadm_id
),

-- CTE 2: Filter for the final patient cohort based on demographics and admission length
cohort_admissions AS (
    SELECT
        adm.hadm_id,
        adm.admittime,
        adm.dischtime
    FROM `physionet-data.mimiciv_3_1_hosp.admissions` AS adm
    INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` AS pat
        ON adm.subject_id = pat.subject_id
    INNER JOIN hadm_with_diagnoses AS dx
        ON adm.hadm_id = dx.hadm_id
    WHERE
        pat.gender = 'M'
        AND (EXTRACT(YEAR FROM adm.admittime) - pat.anchor_year) + pat.anchor_age BETWEEN 58 AND 68
        AND DATETIME_DIFF(adm.dischtime, adm.admittime, HOUR) >= 72
),

-- CTE 3: Identify cohort admissions where a GLP-1 agonist was started in the specified windows
glp1_starts AS (
    SELECT
        cohort.hadm_id,
        MAX(CASE
            WHEN DATETIME_DIFF(pres.starttime, cohort.admittime, HOUR) BETWEEN 0 AND 72
            THEN 1
            ELSE 0
        END) AS started_first_72h,
        MAX(CASE
            WHEN DATETIME_DIFF(cohort.dischtime, pres.starttime, HOUR) BETWEEN 0 AND 12
            THEN 1
            ELSE 0
        END) AS started_final_12h
    FROM cohort_admissions AS cohort
    INNER JOIN `physionet-data.mimiciv_3_1_hosp.prescriptions` AS pres
        ON cohort.hadm_id = pres.hadm_id
    WHERE
        (
            LOWER(pres.drug) LIKE '%semaglutide%' OR
            LOWER(pres.drug) LIKE '%ozempic%' OR
            LOWER(pres.drug) LIKE '%rybelsus%' OR
            LOWER(pres.drug) LIKE '%wegovy%' OR
            LOWER(pres.drug) LIKE '%liraglutide%' OR
            LOWER(pres.drug) LIKE '%victoza%' OR
            LOWER(pres.drug) LIKE '%saxenda%' OR
            LOWER(pres.drug) LIKE '%dulaglutide%' OR
            LOWER(pres.drug) LIKE '%trulicity%' OR
            LOWER(pres.drug) LIKE '%exenatide%' OR
            LOWER(pres.drug) LIKE '%byetta%' OR
            LOWER(pres.drug) LIKE '%bydureon%' OR
            LOWER(pres.drug) LIKE '%lixisenatide%' OR
            LOWER(pres.drug) LIKE '%adlyxin%' OR
            LOWER(pres.drug) LIKE '%tirzepatide%' OR
            LOWER(pres.drug) LIKE '%mounjaro%'
        )
        -- Ensure the prescription starts during the admission
        AND pres.starttime >= cohort.admittime AND pres.starttime <= cohort.dischtime
    GROUP BY cohort.hadm_id
),

-- CTE 4: Aggregate the counts for the final calculation
final_counts AS (
    SELECT
        COUNT(cohort.hadm_id) AS total_cohort_admissions,
        SUM(COALESCE(glp1.started_first_72h, 0)) AS count_first_72h,
        SUM(COALESCE(glp1.started_final_12h, 0)) AS count_final_12h
    FROM cohort_admissions AS cohort
    LEFT JOIN glp1_starts AS glp1
        ON cohort.hadm_id = glp1.hadm_id
)

-- Final SELECT to calculate and display the percentages and difference
SELECT
    SAFE_DIVIDE(count_first_72h, total_cohort_admissions) * 100 AS pct_started_first_72h,
    SAFE_DIVIDE(count_final_12h, total_cohort_admissions) * 100 AS pct_started_final_12h,
    (SAFE_DIVIDE(count_first_72h, total_cohort_admissions) * 100) -
    (SAFE_DIVIDE(count_final_12h, total_cohort_admissions) * 100) AS absolute_diff_pp
FROM final_counts;