WITH drug_classes AS (
    SELECT 'metformin' AS drug_class UNION ALL
    SELECT 'sulfonylureas' UNION ALL
    SELECT 'dpp4' UNION ALL
    SELECT 'sglt2'
),
cohort AS (
    SELECT a.hadm_id, a.subject_id, a.admittime, a.dischtime
    FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
    INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
        ON a.subject_id = p.subject_id
    WHERE p.gender = 'F'
      AND p.anchor_age BETWEEN 68 AND 78
      AND a.admittime IS NOT NULL
      AND a.dischtime IS NOT NULL
      AND TIMESTAMP_DIFF(a.dischtime, a.admittime, HOUR) >= 12
),
total_admissions AS (
    SELECT COUNT(*) AS total FROM cohort
),
emar_data AS (
    SELECT 
        c.hadm_id,
        e.medication,
        e.charttime,
        CASE 
            WHEN e.charttime BETWEEN c.admittime AND TIMESTAMP_ADD(c.admittime, INTERVAL 48 HOUR) THEN 'first48'
            WHEN e.charttime BETWEEN TIMESTAMP_SUB(c.dischtime, INTERVAL 12 HOUR) AND c.dischtime THEN 'last12'
        END AS period,
        CASE 
            WHEN LOWER(e.medication) LIKE '%metformin%' THEN 'metformin'
            WHEN LOWER(e.medication) LIKE '%glipizide%' OR LOWER(e.medication) LIKE '%glyburide%' OR LOWER(e.medication) LIKE '%glimepiride%' THEN 'sulfonylureas'
            WHEN LOWER(e.medication) LIKE '%sitagliptin%' OR LOWER(e.medication) LIKE '%saxagliptin%' OR LOWER(e.medication) LIKE '%linagliptin%' OR LOWER(e.medication) LIKE '%alogliptin%' OR LOWER(e.medication) LIKE '%vildagliptin%' THEN 'dpp4'
            WHEN LOWER(e.medication) LIKE '%empagliflozin%' OR LOWER(e.medication) LIKE '%canagliflozin%' OR LOWER(e.medication) LIKE '%dapagliflozin%' OR LOWER(e.medication) LIKE '%ertugliflozin%' THEN 'sglt2'
        END AS drug_class
    FROM cohort c
    INNER JOIN `physionet-data.mimiciv_3_1_hosp.emar` e
        ON c.subject_id = e.subject_id AND c.hadm_id = e.hadm_id
    WHERE 
        (e.charttime BETWEEN c.admittime AND TIMESTAMP_ADD(c.admittime, INTERVAL 48 HOUR))
        OR (e.charttime BETWEEN TIMESTAMP_SUB(c.dischtime, INTERVAL 12 HOUR) AND c.dischtime)
),
drug_period_flags AS (
    SELECT 
        hadm_id,
        drug_class,
        MAX(CASE WHEN period = 'first48' THEN 1 ELSE 0 END) AS in_first48,
        MAX(CASE WHEN period = 'last12' THEN 1 ELSE 0 END) AS in_last12
    FROM emar_data
    GROUP BY hadm_id, drug_class
),
drug_counts AS (
    SELECT 
        drug_class,
        SUM(in_first48) AS count_first48,
        SUM(in_last12) AS count_last12
    FROM drug_period_flags
    GROUP BY drug_class
)
SELECT 
    dc.drug_class,
    COALESCE( (dc_count.count_first48 * 100.0 / ta.total), 0) AS prevalence_first48,
    COALESCE( (dc_count.count_last12 * 100.0 / ta.total), 0) AS prevalence_last12,
    COALESCE( (dc_count.count_last12 * 100.0 / ta.total - dc_count.count_first48 * 100.0 / ta.total), 0) AS net_change
FROM drug_classes dc
CROSS JOIN total_admissions ta
LEFT JOIN drug_counts dc_count ON dc.drug_class = dc_count.drug_class
ORDER BY dc.drug_class;