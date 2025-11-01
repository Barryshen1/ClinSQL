WITH eligible_patients AS (
    SELECT subject_id
    FROM `physionet-data.mimiciv_3_1_hosp.patients`
    WHERE gender = 'F'
        AND anchor_age BETWEEN 42 AND 52
),
troponin_events AS (
    SELECT 
        le.subject_id,
        le.labevent_id,
        le.charttime,
        le.valuenum
    FROM `physionet-data.mimiciv_3_1_hosp.labevents` le
    INNER JOIN eligible_patients ep 
        ON le.subject_id = ep.subject_id
    WHERE le.itemid = 50911  -- hs-Troponin T
        AND le.valuenum IS NOT NULL
        AND le.valueuom = 'ng/mL'  -- Ensure correct unit
),
ranked_troponin AS (
    SELECT 
        subject_id,
        valuenum,
        ROW_NUMBER() OVER (
            PARTITION BY subject_id 
            ORDER BY charttime, labevent_id
        ) AS rn
    FROM troponin_events
),
categorized_troponin AS (
    SELECT 
        subject_id,
        CASE 
            WHEN valuenum < 0.014 THEN 'Normal'
            WHEN valuenum >= 0.014 AND valuenum < 0.04 THEN 'Borderline'
            WHEN valuenum >= 0.04 THEN 'Myocardial Injury'
        END AS category
    FROM ranked_troponin
    WHERE rn = 1  -- First test per patient
)
SELECT 
    category,
    COUNT(subject_id) AS patient_count
FROM categorized_troponin
GROUP BY category
ORDER BY category;