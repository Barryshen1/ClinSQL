WITH cohort AS (
    SELECT DISTINCT a.hadm_id
    FROM `physionet-data.mimiciv_3_1_hosp.patients` p
    JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a ON p.subject_id = a.subject_id
    JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d ON a.hadm_id = d.hadm_id
    WHERE p.gender = 'F'
      AND p.anchor_age BETWEEN 64 AND 74
      AND d.seq_num = 1
      AND d.icd_version = 10
      AND (d.icd_code LIKE 'I21%' OR d.icd_code LIKE 'I22%')
),
first_troponin AS (
    SELECT 
        l.hadm_id,
        l.valuenum,
        ROW_NUMBER() OVER (PARTITION BY l.hadm_id ORDER BY l.charttime) AS rn
    FROM `physionet-data.mimiciv_3_1_hosp.labevents` l
    WHERE l.itemid = 50911
      AND l.hadm_id IN (SELECT hadm_id FROM cohort)
      AND l.valuenum IS NOT NULL
)
SELECT 
    CASE 
        WHEN valuenum <= 0.014 THEN 'Normal'
        WHEN valuenum BETWEEN 0.015 AND 0.052 THEN 'Borderline'
        WHEN valuenum > 0.052 THEN 'Myocardial Injury'
    END AS category,
    COUNT(*) AS count,
    ROUND(COUNT(*) * 100.0 / (SELECT COUNT(*) FROM first_troponin WHERE rn = 1), 2) AS percentage
FROM first_troponin
WHERE rn = 1
GROUP BY category;