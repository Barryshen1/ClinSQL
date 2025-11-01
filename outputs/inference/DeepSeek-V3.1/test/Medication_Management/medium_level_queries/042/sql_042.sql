WITH cohort AS (
    SELECT 
        p.subject_id, 
        a.hadm_id, 
        a.admittime, 
        a.dischtime
    FROM `physionet-data.mimiciv_3_1_hosp.patients` p
    INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a
        ON p.subject_id = a.subject_id
    WHERE p.gender = 'F'
        AND p.anchor_age BETWEEN 51 AND 61
        AND EXISTS (
            SELECT 1
            FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` di
            WHERE di.subject_id = a.subject_id
                AND di.hadm_id = a.hadm_id
                AND (
                    (di.icd_version = 10 AND di.icd_code LIKE 'E11%') 
                    OR (di.icd_version = 9 AND di.icd_code LIKE '250%')
                )
        )
        AND EXISTS (
            SELECT 1
            FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` di
            WHERE di.subject_id = a.subject_id
                AND di.hadm_id = a.hadm_id
                AND (
                    (di.icd_version = 10 AND di.icd_code LIKE 'I50%') 
                    OR (di.icd_version = 9 AND di.icd_code LIKE '428%')
                )
        )
),

insulin_orders AS (
    SELECT 
        subject_id,
        hadm_id,
        starttime,
        stoptime,
        'insulin' AS drug_class
    FROM `physionet-data.mimiciv_3_1_hosp.prescriptions`
    WHERE LOWER(drug) LIKE '%insulin%'
),

oral_orders AS (
    SELECT 
        subject_id,
        hadm_id,
        starttime,
        stoptime,
        'oral' AS drug_class
    FROM `physionet-data.mimiciv_3_1_hosp.prescriptions`
    WHERE LOWER(drug) LIKE '%metformin%' 
        OR LOWER(drug) LIKE '%glipizide%'
        OR LOWER(drug) LIKE '%glyburide%'
        OR LOWER(drug) LIKE '%glimepiride%'
        OR LOWER(drug) LIKE '%pioglitazone%'
        OR LOWER(drug) LIKE '%rosiglitazone%'
        OR LOWER(drug) LIKE '%sitagliptin%'
        OR LOWER(drug) LIKE '%saxagliptin%'
        OR LOWER(drug) LIKE '%linagliptin%'
        OR LOWER(drug) LIKE '%empagliflozin%'
        OR LOWER(drug) LIKE '%canagliflozin%'
        OR LOWER(drug) LIKE '%dapagliflozin%'
        OR LOWER(drug) LIKE '%repaglinide%'
        OR LOWER(drug) LIKE '%nateglinide%'
        OR LOWER(drug) LIKE '%acarbose%'
),

all_orders AS (
    SELECT * FROM insulin_orders
    UNION ALL
    SELECT * FROM oral_orders
),

first_48h AS (
    SELECT 
        c.subject_id,
        c.hadm_id,
        MAX(CASE WHEN ao.drug_class = 'insulin' THEN 1 ELSE 0 END) AS insulin_flag,
        MAX(CASE WHEN ao.drug_class = 'oral' THEN 1 ELSE 0 END) AS oral_flag
    FROM cohort c
    LEFT JOIN all_orders ao
        ON c.subject_id = ao.subject_id
        AND c.hadm_id = ao.hadm_id
        AND ao.starttime BETWEEN c.admittime AND DATETIME_ADD(c.admittime, INTERVAL 48 HOUR)
    GROUP BY c.subject_id, c.hadm_id
),

final_24h AS (
    SELECT 
        c.subject_id,
        c.hadm_id,
        MAX(CASE WHEN ao.drug_class = 'insulin' THEN 1 ELSE 0 END) AS insulin_flag,
        MAX(CASE WHEN ao.drug_class = 'oral' THEN 1 ELSE 0 END) AS oral_flag
    FROM cohort c
    LEFT JOIN all_orders ao
        ON c.subject_id = ao.subject_id
        AND c.hadm_id = ao.hadm_id
        AND ao.starttime BETWEEN DATETIME_SUB(c.dischtime, INTERVAL 24 HOUR) AND c.dischtime
    GROUP BY c.subject_id, c.hadm_id
),

drug_status AS (
    SELECT 
        c.subject_id,
        c.hadm_id,
        ao.drug_class,
        CASE 
            WHEN ao.starttime < c.admittime AND (ao.stoptime IS NULL OR ao.stoptime >= c.dischtime) THEN 'continued'
            WHEN ao.starttime >= c.admittime THEN 'initiated'
            WHEN ao.stoptime < c.dischtime AND ao.stoptime >= c.admittime THEN 'discontinued'
        END AS status
    FROM cohort c
    INNER JOIN all_orders ao
        ON c.subject_id = ao.subject_id
        AND c.hadm_id = ao.hadm_id
    WHERE ao.starttime IS NOT NULL
),

status_agg AS (
    SELECT 
        subject_id,
        hadm_id,
        drug_class,
        -- For each drug class per admission, if any order is continued, mark as continued; else initiated; else discontinued.
        -- But note: a patient may have multiple orders. We want to classify the drug class overall.
        CASE 
            WHEN MAX(CASE WHEN status = 'continued' THEN 1 ELSE 0 END) = 1 THEN 'continued'
            WHEN MAX(CASE WHEN status = 'initiated' THEN 1 ELSE 0 END) = 1 THEN 'initiated'
            WHEN MAX(CASE WHEN status = 'discontinued' THEN 1 ELSE 0 END) = 1 THEN 'discontinued'
        END AS status
    FROM drug_status
    GROUP BY subject_id, hadm_id, drug_class
)

SELECT 
    (SELECT COUNT(*) FROM cohort) AS total_patients,
    -- First 48h
    ROUND(100.0 * SUM(f48.insulin_flag) / (SELECT COUNT(*) FROM cohort), 2) AS pct_insulin_first_48h,
    ROUND(100.0 * SUM(f48.oral_flag) / (SELECT COUNT(*) FROM cohort), 2) AS pct_oral_first_48h,

    -- Final 24h
    ROUND(100.0 * SUM(f24.insulin_flag) / (SELECT COUNT(*) FROM cohort), 2) AS pct_insulin_final_24h,
    ROUND(100.0 * SUM(f24.oral_flag) / (SELECT COUNT(*) FROM cohort), 2) AS pct_oral_final_24h,

    -- Continued/Initiated/Discontinued for insulin
    SUM(CASE WHEN sa.status = 'continued' AND sa.drug_class = 'insulin' THEN 1 ELSE 0 END) AS insulin_continued,
    SUM(CASE WHEN sa.status = 'initiated' AND sa.drug_class = 'insulin' THEN 1 ELSE 0 END) AS insulin_initiated,
    SUM(CASE WHEN sa.status = 'discontinued' AND sa.drug_class = 'insulin' THEN 1 ELSE 0 END) AS insulin_discontinued,

    -- Continued/Initiated/Discontinued for oral
    SUM(CASE WHEN sa.status = 'continued' AND sa.drug_class = 'oral' THEN 1 ELSE 0 END) AS oral_continued,
    SUM(CASE WHEN sa.status = 'initiated' AND sa.drug_class = 'oral' THEN 1 ELSE 0 END) AS oral_initiated,
    SUM(CASE WHEN sa.status = 'discontinued' AND sa.drug_class = 'oral' THEN 1 ELSE 0 END) AS oral_discontinued

FROM cohort c
LEFT JOIN first_48h f48
    ON c.subject_id = f48.subject_id AND c.hadm_id = f48.hadm_id
LEFT JOIN final_24h f24
    ON c.subject_id = f24.subject_id AND c.hadm_id = f24.hadm_id
LEFT JOIN status_agg sa
    ON c.subject_id = sa.subject_id AND c.hadm_id = sa.hadm_id
GROUP BY total_patients;