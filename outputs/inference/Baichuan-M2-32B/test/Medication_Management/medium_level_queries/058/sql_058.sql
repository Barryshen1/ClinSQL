WITH cohort AS (
    SELECT 
        a.hadm_id,
        a.subject_id,
        a.admittime,
        a.dischtime,
        p.gender,
        (EXTRACT(YEAR FROM a.admittime) - p.anchor_year + p.anchor_age) AS age
    FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
    INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` p 
        ON a.subject_id = p.subject_id
    INNER JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d1 
        ON a.hadm_id = d1.hadm_id 
        AND d1.icd_code LIKE 'E11%' AND d1.icd_version = 10
    INNER JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d2 
        ON a.hadm_id = d2.hadm_id 
        AND d2.icd_code LIKE 'I50%' AND d2.icd_version = 10
    WHERE 
        p.gender = 'M'
        AND (EXTRACT(YEAR FROM a.admittime) - p.anchor_year + p.anchor_age) BETWEEN 36 AND 46
),
total_patients AS (
    SELECT COUNT(DISTINCT subject_id) AS total FROM cohort
),
prescriptions_with_class AS (
    SELECT 
        c.hadm_id,
        c.subject_id,
        c.admittime,
        c.dischtime,
        pr.starttime,
        pr.drug,
        CASE 
            WHEN LOWER(pr.drug) LIKE '%insulin%' THEN 'Insulin'
            WHEN LOWER(pr.drug) LIKE '%metformin%' THEN 'Metformin'
            WHEN LOWER(pr.drug) LIKE '%glipizide%' OR LOWER(pr.drug) LIKE '%glyburide%' OR LOWER(pr.drug) LIKE '%glimepiride%' THEN 'Sulfonylureas'
            WHEN LOWER(pr.drug) LIKE '%sitagliptin%' OR LOWER(pr.drug) LIKE '%saxagliptin%' OR LOWER(pr.drug) LIKE '%linagliptin%' OR LOWER(pr.drug) LIKE '%alogliptin%' THEN 'DPP-4 inhibitors'
            WHEN LOWER(pr.drug) LIKE '%empagliflozin%' OR LOWER(pr.drug) LIKE '%dapagliflozin%' OR LOWER(pr.drug) LIKE '%canagliflozin%' THEN 'SGLT2 inhibitors'
            WHEN LOWER(pr.drug) LIKE '%pioglitazone%' OR LOWER(pr.drug) LIKE '%rosiglitazone%' THEN 'Thiazolidinediones'
            WHEN LOWER(pr.drug) LIKE '%liraglutide%' OR LOWER(pr.drug) LIKE '%exenatide%' OR LOWER(pr.drug) LIKE '%semaglutide%' THEN 'GLP-1 receptor agonists'
            ELSE 'Other'
        END AS antidiabetic_class
    FROM cohort c
    LEFT JOIN `physionet-data.mimiciv_3_1_hosp.prescriptions` pr 
        ON c.hadm_id = pr.hadm_id 
        AND c.subject_id = pr.subject_id
        AND pr.starttime BETWEEN c.admittime AND c.dischtime
),
patient_class_flags AS (
    SELECT 
        subject_id,
        hadm_id,
        antidiabetic_class,
        MAX(CASE WHEN starttime BETWEEN admittime AND admittime + INTERVAL 12 HOUR THEN 1 ELSE 0 END) AS initiated_first12h,
        MAX(CASE WHEN starttime BETWEEN GREATEST(admittime, dischtime - INTERVAL 48 HOUR) AND dischtime THEN 1 ELSE 0 END) AS initiated_final48h
    FROM prescriptions_with_class
    GROUP BY subject_id, hadm_id, antidiabetic_class
),
aggregated AS (
    SELECT 
        antidiabetic_class,
        COUNT(DISTINCT CASE WHEN initiated_first12h = 1 THEN subject_id END) AS initiations_first12h,
        COUNT(DISTINCT CASE WHEN initiated_final48h = 1 THEN subject_id END) AS initiations_final48h
    FROM patient_class_flags
    GROUP BY antidiabetic_class
),
classes AS (
    SELECT 'Insulin' AS class
    UNION ALL SELECT 'Metformin'
    UNION ALL SELECT 'Sulfonylureas'
    UNION ALL SELECT 'DPP-4 inhibitors'
    UNION ALL SELECT 'SGLT2 inhibitors'
    UNION ALL SELECT 'Thiazolidinediones'
    UNION ALL SELECT 'GLP-1 receptor agonists'
    UNION ALL SELECT 'Other'
)
SELECT 
    c.class AS antidiabetic_class,
    COALESCE(a.initiations_first12h, 0) AS initiations_first12h,
    COALESCE(a.initiations_final48h, 0) AS initiations_final48h,
    t.total AS total_patients,
    (COALESCE(a.initiations_first12h, 0) * 100.0 / t.total) AS rate_first12h,
    (COALESCE(a.initiations_final48h, 0) * 100.0 / t.total) AS rate_final48h,
    (COALESCE(a.initiations_final48h, 0) - COALESCE(a.initiations_first12h, 0)) * 100.0 / t.total AS net_change_pp
FROM classes c
CROSS JOIN total_patients t
LEFT JOIN aggregated a ON c.class = a.antidiabetic_class
ORDER BY c.class;