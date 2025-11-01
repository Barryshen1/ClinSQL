WITH cohort_patients AS (
    SELECT 
        p.subject_id,
        a.hadm_id,
        a.admittime,
        a.dischtime,
        p.gender,
        p.anchor_year,
        p.anchor_age,
        EXTRACT(YEAR FROM a.admittime) - (p.anchor_year - p.anchor_age) AS age_at_admission
    FROM `physionet-data.mimiciv_3_1_hosp.patients` p
    INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a 
        ON p.subject_id = a.subject_id
    WHERE p.gender = 'M'
        AND EXTRACT(YEAR FROM a.admittime) - (p.anchor_year - p.anchor_age) BETWEEN 45 AND 55
        AND a.dischtime IS NOT NULL  -- Ensure dischtime is not null for the final window
),
cohort_with_diagnoses AS (
    SELECT 
        c.*
    FROM cohort_patients c
    WHERE 
        -- Diabetes: ICD-10 E10-E14 or ICD-9 250.*
        EXISTS (
            SELECT 1 
            FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
            WHERE d.hadm_id = c.hadm_id
                AND ( 
                    (d.icd_version = 10 AND d.icd_code BETWEEN 'E10' AND 'E14') 
                    OR 
                    (d.icd_version = 9 AND d.icd_code LIKE '250%')
                )
        )
        AND
        -- Heart failure: ICD-10 I50.* or ICD-9 428.*
        EXISTS (
            SELECT 1 
            FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
            WHERE d.hadm_id = c.hadm_id
                AND (
                    (d.icd_version = 10 AND d.icd_code LIKE 'I50%') 
                    OR 
                    (d.icd_version = 9 AND d.icd_code LIKE '428%')
                )
        )
),
drug_orders AS (
    SELECT 
        subject_id,
        hadm_id,
        starttime,
        -- Flag for drug class
        CASE 
            WHEN LOWER(drug) LIKE '%insulin%' AND UPPER(TRIM(route)) IN ('IV', 'SC') THEN 'insulin'
            WHEN REGEXP_CONTAINS(LOWER(drug), r'metformin|glipizide|glyburide|glimepiride|pioglitazone|rosiglitazone|sitagliptin|linagliptin|dapagliflozin|empagliflozin') AND UPPER(TRIM(route)) = 'PO' THEN 'oral_antidiabetic'
            ELSE NULL 
        END AS drug_class
    FROM `physionet-data.mimiciv_3_1_hosp.prescriptions`
    WHERE 
        starttime IS NOT NULL
        AND order_status IN ('active', 'completed')  -- Only consider active or completed orders
        AND drug_class IS NOT NULL
),
patient_drug_flags AS (
    SELECT 
        c.subject_id,
        c.hadm_id,
        -- First 12h window: from admittime to admittime + 12h
        MAX(CASE WHEN d.drug_class = 'insulin' AND d.starttime BETWEEN c.admittime AND c.admittime + INTERVAL 12 HOUR THEN 1 ELSE 0 END) AS insulin_first12h,
        MAX(CASE WHEN d.drug_class = 'oral_antidiabetic' AND d.starttime BETWEEN c.admittime AND c.admittime + INTERVAL 12 HOUR THEN 1 ELSE 0 END) AS oral_antidiabetic_first12h,
        -- Final 72h window: from dischtime - 72h to dischtime
        MAX(CASE WHEN d.drug_class = 'insulin' AND d.starttime BETWEEN c.dischtime - INTERVAL 72 HOUR AND c.dischtime THEN 1 ELSE 0 END) AS insulin_final72h,
        MAX(CASE WHEN d.drug_class = 'oral_antidiabetic' AND d.starttime BETWEEN c.dischtime - INTERVAL 72 HOUR AND c.dischtime THEN 1 ELSE 0 END) AS oral_antidiabetic_final72h
    FROM cohort_with_diagnoses c
    LEFT JOIN drug_orders d 
        ON c.subject_id = d.subject_id 
        AND c.hadm_id = d.hadm_id
    GROUP BY c.subject_id, c.hadm_id
),
rates AS (
    SELECT 
        drug_class,
        time_window,
        COUNT(CASE WHEN flag = 1 THEN 1 END) * 100.0 / COUNT(*) AS rate_percent
    FROM patient_drug_flags
    CROSS JOIN UNNEST([
        STRUCT('insulin' AS drug_class, 'first12h' AS time_window, insulin_first12h AS flag),
        STRUCT('insulin', 'final72h', insulin_final72h),
        STRUCT('oral_antidiabetic', 'first12h', oral_antidiabetic_first12h),
        STRUCT('oral_antidiabetic', 'final72h', oral_antidiabetic_final72h)
    ]) AS unpivoted
    GROUP BY drug_class, time_window
)
SELECT 
    drug_class,
    MAX(CASE WHEN time_window = 'first12h' THEN rate_percent END) AS rate_first12h,
    MAX(CASE WHEN time_window = 'final72h' THEN rate_percent END) AS rate_final72h,
    MAX(CASE WHEN time_window = 'first12h' THEN rate_percent END) - MAX(CASE WHEN time_window = 'final72h' THEN rate_percent END) AS pp_difference
FROM rates
GROUP BY drug_class
ORDER BY drug_class;