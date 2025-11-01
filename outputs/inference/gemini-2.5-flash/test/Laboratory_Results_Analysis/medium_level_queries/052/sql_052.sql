WITH cohort_admissions AS (
    SELECT DISTINCT
        adm.subject_id,
        adm.hadm_id
    FROM `physionet-data.mimiciv_3_1_hosp.admissions` AS adm
    INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` AS pat
        ON adm.subject_id = pat.subject_id
    WHERE
        pat.gender = 'M'
        AND pat.anchor_age BETWEEN 76 AND 86 -- Age filtering
        AND EXISTS ( -- Check if ANY diagnosis for this admission is AMI
            SELECT 1
            FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` AS diag
            WHERE
                diag.subject_id = adm.subject_id
                AND diag.hadm_id = adm.hadm_id
                AND (
                       (diag.icd_version = 9 AND diag.icd_code LIKE '410%') -- ICD-9 for Acute MI
                    OR (diag.icd_version = 10 AND (diag.icd_code LIKE 'I21%' OR diag.icd_code LIKE 'I22%')) -- ICD-10 for Acute/Subsequent MI
                )
        )
),
first_troponin AS (
    SELECT
        le.subject_id,
        le.hadm_id,
        le.valuenum,
        le.charttime,
        ROW_NUMBER() OVER (PARTITION BY le.subject_id, le.hadm_id ORDER BY le.charttime, le.labevent_id) AS rn
    FROM `physionet-data.mimiciv_3_1_hosp.labevents` AS le
    INNER JOIN cohort_admissions AS ca
        ON le.subject_id = ca.subject_id AND le.hadm_id = ca.hadm_id
    WHERE
        le.itemid = 51003 -- Item ID for Troponin I (confirmed by d_labitems lookup)
        AND le.valuenum IS NOT NULL -- Ensure a numeric value exists
        AND le.valuenum >= 0 -- Troponin values are typically non-negative
),
cleaned_first_troponin AS (
    SELECT
        valuenum,
        CASE
            WHEN valuenum <= 0.04 THEN 'Normal'
            WHEN valuenum > 0.04 AND valuenum < 0.40 THEN 'Borderline'
            WHEN valuenum >= 0.40 THEN 'Elevated'
            ELSE 'Unknown' -- Should not be reached with valuenum >= 0 filter
        END AS troponin_category
    FROM first_troponin
    WHERE rn = 1
),
-- CTE to calculate category-specific counts and percentages
category_stats AS (
    SELECT
        troponin_category,
        COUNT(valuenum) AS category_count,
        ROUND(COUNT(valuenum) * 100.0 / SUM(COUNT(valuenum)) OVER(), 2) AS category_percentage
    FROM cleaned_first_troponin
    GROUP BY troponin_category
),
-- CTE to calculate overall statistics
overall_stats AS (
    SELECT
        COUNT(valuenum) AS total_count_troponin,
        ROUND(AVG(valuenum), 3) AS mean_troponin,
        ROUND(APPROX_QUANTILES(valuenum, 100)[OFFSET(50)], 3) AS median_troponin, -- Median (50th percentile)
        ROUND(APPROX_QUANTILES(valuenum, 100)[OFFSET(75)] - APPROX_QUANTILES(valuenum, 100)[OFFSET(25)], 3) AS iqr_troponin -- IQR (75th - 25th percentile)
    FROM cleaned_first_troponin
)
-- Final SELECT statement to combine results
SELECT
    cs.troponin_category,
    cs.category_count,
    cs.category_percentage,
    os.total_count_troponin,
    os.mean_troponin,
    os.median_troponin,
    os.iqr_troponin
FROM category_stats AS cs
CROSS JOIN overall_stats AS os
ORDER BY
    CASE cs.troponin_category
        WHEN 'Normal' THEN 1
        WHEN 'Borderline' THEN 2
        WHEN 'Elevated' THEN 3
        ELSE 4
    END;