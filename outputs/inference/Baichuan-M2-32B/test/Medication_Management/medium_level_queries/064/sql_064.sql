WITH medication_classes AS (
    SELECT 'metformin' AS class
    UNION ALL SELECT 'sulfonylurea'
    UNION ALL SELECT 'dpp4'
    UNION ALL SELECT 'sglt2'
    UNION ALL SELECT 'thiazolidinedione'
),
cohort AS (
    SELECT 
        p.subject_id,
        a.hadm_id,
        a.admittime,
        a.dischtime,
        a.admittime AS first_72h_start,
        LEAST(a.admittime + INTERVAL 72 HOUR, a.dischtime) AS first_72h_end,
        GREATEST(a.admittime, a.dischtime - INTERVAL 48 HOUR) AS last_48h_start,
        a.dischtime AS last_48h_end
    FROM `physionet-data.mimiciv_3_1_hosp.patients` p
    INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a 
        ON p.subject_id = a.subject_id
    WHERE p.anchor_age BETWEEN 71 AND 81
        AND p.gender = 'M'
        AND a.hadm_id IN (
            SELECT d1.hadm_id
            FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d1
            INNER JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` d2 
                ON d1.icd_code = d2.icd_code AND d1.icd_version = d2.icd_version
            WHERE d2.long_title LIKE '%diabetes%'
            AND d1.hadm_id IN (
                SELECT d3.hadm_id
                FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d3
                INNER JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` d4 
                    ON d3.icd_code = d4.icd_code AND d3.icd_version = d4.icd_version
                WHERE d4.long_title LIKE '%heart failure%'
            )
        )
),
first_orders AS (
    SELECT 
        p.hadm_id,
        CASE 
            WHEN p.drug LIKE '%metformin%' THEN 'metformin'
            WHEN p.drug LIKE '%glipizide%' OR p.drug LIKE '%glyburide%' OR p.drug LIKE '%glimepiride%' OR p.drug LIKE '%repaglinide%' OR p.drug LIKE '%nateglinide%' THEN 'sulfonylurea'
            WHEN p.drug LIKE '%sitagliptin%' OR p.drug LIKE '%saxagliptin%' OR p.drug LIKE '%linagliptin%' OR p.drug LIKE '%alogliptin%' OR p.drug LIKE '%vildagliptin%' THEN 'dpp4'
            WHEN p.drug LIKE '%canagliflozin%' OR p.drug LIKE '%dapagliflozin%' OR p.drug LIKE '%empagliflozin%' OR p.drug LIKE '%ertugliflozin%' THEN 'sglt2'
            WHEN p.drug LIKE '%pioglitazone%' OR p.drug LIKE '%rosiglitazone%' THEN 'thiazolidinedione'
            ELSE NULL
        END AS medication_class,
        MIN(p.starttime) AS first_order_time
    FROM `physionet-data.mimiciv_3_1_hosp.prescriptions` p
    WHERE p.drug IS NOT NULL
    GROUP BY p.hadm_id, medication_class
    HAVING medication_class IS NOT NULL
),
cohort_classes AS (
    SELECT 
        c.*,
        mc.class
    FROM cohort c
    CROSS JOIN medication_classes mc
),
cohort_orders AS (
    SELECT 
        cc.*,
        fo.first_order_time
    FROM cohort_classes cc
    LEFT JOIN first_orders fo 
        ON cc.hadm_id = fo.hadm_id 
        AND cc.class = fo.medication_class
),
window_flags AS (
    SELECT 
        class,
        hadm_id,
        CASE 
            WHEN first_order_time BETWEEN first_72h_start AND first_72h_end THEN 1
            ELSE 0
        END AS initiated_first_72h,
        CASE 
            WHEN first_order_time BETWEEN last_48h_start AND last_48h_end THEN 1
            ELSE 0
        END AS initiated_last_48h
    FROM cohort_orders
),
cohort_summary AS (
    SELECT COUNT(DISTINCT hadm_id) AS total_patients
    FROM cohort
),
aggregated AS (
    SELECT 
        class,
        'first_72h' AS time_window,
        SUM(initiated_first_72h) AS num_initiations
    FROM window_flags
    GROUP BY class, time_window

    UNION ALL

    SELECT 
        class,
        'last_48h' AS time_window,
        SUM(initiated_last_48h) AS num_initiations
    FROM window_flags
    GROUP BY class, time_window
)
SELECT 
    a.class AS medication_class,
    a.time_window,
    (a.num_initiations * 100.0 / cs.total_patients) AS initiation_rate_percent
FROM aggregated a
CROSS JOIN cohort_summary cs
ORDER BY a.class, a.time_window;