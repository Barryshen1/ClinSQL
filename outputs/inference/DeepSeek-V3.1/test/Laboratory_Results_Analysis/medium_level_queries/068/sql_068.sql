WITH first_troponin AS (
    SELECT 
        p.subject_id,
        FIRST_VALUE(le.valuenum) OVER (
            PARTITION BY le.subject_id 
            ORDER BY le.charttime
        ) AS first_troponin_value
    FROM `physionet-data.mimiciv_3_1_hosp.patients` p
    INNER JOIN `physionet-data.mimiciv_3_1_hosp.labevents` le
        ON p.subject_id = le.subject_id
    WHERE 
        p.gender = 'F'
        AND p.anchor_age BETWEEN 42 AND 52
        AND le.itemid = 50911  -- hs-Troponin T
        AND le.valuenum IS NOT NULL
),
categorized AS (
    SELECT 
        subject_id,
        CASE 
            WHEN first_troponin_value < 0.014 THEN 'Normal'
            WHEN first_troponin_value >= 0.014 AND first_troponin_value < 0.04 THEN 'Borderline'
            WHEN first_troponin_value >= 0.04 THEN 'Myocardial Injury'
        END AS troponin_category
    FROM first_troponin
    GROUP BY subject_id, first_troponin_value
)
SELECT 
    troponin_category,
    COUNT(DISTINCT subject_id) AS patient_count
FROM categorized
GROUP BY troponin_category
ORDER BY troponin_category;