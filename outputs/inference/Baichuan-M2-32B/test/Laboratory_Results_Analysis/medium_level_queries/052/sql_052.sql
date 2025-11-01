WITH patients AS (
    SELECT subject_id, gender, anchor_age
    FROM `physionet-data.mimiciv_3_1_hosp`.patients
    WHERE gender = 'M' AND anchor_age BETWEEN 76 AND 86
),
admissions AS (
    SELECT a.hadm_id, a.subject_id, a.admittime
    FROM `physionet-data.mimiciv_3_1_hosp`.admissions a
    JOIN patients p ON a.subject_id = p.subject_id
),
ami_admissions AS (
    SELECT DISTINCT d.hadm_id
    FROM `physionet-data.mimiciv_3_1_hosp`.diagnoses_icd d
    JOIN `physionet-data.mimiciv_3_1_hosp`.d_icd_diagnoses dd 
        ON d.icd_code = dd.icd_code AND d.icd_version = dd.icd_version
    WHERE dd.long_title LIKE '%myocardial infarction%'
    AND d.hadm_id IN (SELECT hadm_id FROM admissions)
),
troponin_itemid AS (
    SELECT itemid
    FROM `physionet-data.mimiciv_3_1_hosp`.d_labitems
    WHERE label LIKE '%Troponin I%' AND category LIKE 'Cardiac'
    ORDER BY itemid
    LIMIT 1
),
first_troponin AS (
    SELECT 
        l.hadm_id,
        l.valuenum,
        ROW_NUMBER() OVER (PARTITION BY l.hadm_id ORDER BY l.charttime ASC) AS rn
    FROM `physionet-data.mimiciv_3_1_hosp`.labevents l
    JOIN troponin_itemid t ON l.itemid = t.itemid
    WHERE l.hadm_id IN (SELECT hadm_id FROM ami_admissions)
      AND l.valuenum IS NOT NULL
),
first_troponin_per_admission AS (
    SELECT hadm_id, valuenum
    FROM first_troponin
    WHERE rn = 1
),
categorized AS (
    SELECT 
        hadm_id,
        valuenum,
        CASE 
            WHEN valuenum <= 0.04 THEN 'Normal'
            WHEN valuenum > 0.04 AND valuenum <= 0.40 THEN 'Borderline'
            WHEN valuenum > 0.40 THEN 'Elevated'
            ELSE 'Unknown'
        END AS category
    FROM first_troponin_per_admission
),
category_counts AS (
    SELECT 
        category,
        COUNT(*) AS count,
        COUNT(*) * 100.0 / (SELECT COUNT(*) FROM categorized) AS percentage
    FROM categorized
    GROUP BY category
),
overall_stats AS (
    SELECT 
        COUNT(*) AS total_count,
        AVG(valuenum) AS mean,
        APPROX_QUANTILES(valuenum, 100) AS quantiles
    FROM first_troponin_per_admission
),
overall_stats_expanded AS (
    SELECT 
        total_count,
        mean,
        quantiles[OFFSET(50)] AS median,   -- 50th percentile (median)
        quantiles[OFFSET(25)] AS p25,       -- 25th percentile
        quantiles[OFFSET(75)] AS p75,       -- 75th percentile
        quantiles[OFFSET(75)] - quantiles[OFFSET(25)] AS iqr
    FROM overall_stats
)
SELECT 
    category,
    count,
    percentage,
    NULL AS mean,
    NULL AS median,
    NULL AS iqr
FROM category_counts
UNION ALL
SELECT 
    'Overall' AS category,
    total_count,
    NULL AS percentage,
    mean,
    median,
    iqr
FROM overall_stats_expanded;