WITH cohort AS (
    SELECT 
        adm.subject_id, 
        adm.hadm_id, 
        adm.admittime, 
        adm.dischtime,
        DATETIME_ADD(adm.admittime, INTERVAL 12 HOUR) AS first12h_end,
        DATETIME_SUB(adm.dischtime, INTERVAL 48 HOUR) AS final48h_start
    FROM `physionet-data.mimiciv_3_1_hosp.admissions` adm
    INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` pat
        ON adm.subject_id = pat.subject_id
    WHERE pat.gender = 'M'
        AND pat.anchor_age BETWEEN 64 AND 74
        AND adm.hadm_id IN (
            SELECT hadm_id FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` 
            WHERE icd_code LIKE 'E1%' AND icd_version = 10
        ) -- diabetes
        AND adm.hadm_id IN (
            SELECT hadm_id FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` 
            WHERE icd_code IN ('I50.21','I50.23','I50.31','I50.33','I50.41','I50.43','I50.9') 
                AND icd_version = 10
        ) -- acute HF
),

drug_classes AS (
    SELECT 
        c.hadm_id,
        -- Check for each drug class in first 12h
        MAX(CASE WHEN p.starttime BETWEEN c.admittime AND c.first12h_end AND p.drug LIKE '%insulin%' THEN 1 ELSE 0 END) AS insulin_first12h,
        MAX(CASE WHEN p.starttime BETWEEN c.admittime AND c.first12h_end AND (p.drug LIKE '%metformin%' OR p.drug LIKE '%glucophage%') THEN 1 ELSE 0 END) AS metformin_first12h,
        MAX(CASE WHEN p.starttime BETWEEN c.admittime AND c.first12h_end AND (p.drug LIKE '%glyburide%' OR p.drug LIKE '%glipizide%' OR p.drug LIKE '%glimepiride%' OR p.drug LIKE '%sulfonylurea%') THEN 1 ELSE 0 END) AS sulfonylureas_first12h,
        MAX(CASE WHEN p.starttime BETWEEN c.admittime AND c.first12h_end AND (p.drug LIKE '%sitagliptin%' OR p.drug LIKE '%saxagliptin%' OR p.drug LIKE '%linagliptin%' OR p.drug LIKE '%alogliptin%' OR p.drug LIKE '%dutogliptin%' OR p.drug LIKE '%gemigliptin%' OR p.drug LIKE '%dpp4%' OR p.drug LIKE '%dpp-4%') THEN 1 ELSE 0 END) AS dpp4_first12h,
        MAX(CASE WHEN p.starttime BETWEEN c.admittime AND c.first12h_end AND (p.drug LIKE '%canagliflozin%' OR p.drug LIKE '%dapagliflozin%' OR p.drug LIKE '%empagliflozin%' OR p.drug LIKE '%sglt2%' OR p.drug LIKE '%sglt-2%') THEN 1 ELSE 0 END) AS sglt2_first12h,
        MAX(CASE WHEN p.starttime BETWEEN c.admittime AND c.first12h_end AND (p.drug LIKE '%liraglutide%' OR p.drug LIKE '%dulaglutide%' OR p.drug LIKE '%exenatide%' OR p.drug LIKE '%lixisenatide%' OR p.drug LIKE '%semaglutide%' OR p.drug LIKE '%glp1%' OR p.drug LIKE '%glp-1%') THEN 1 ELSE 0 END) AS glp1_first12h,
        MAX(CASE WHEN p.starttime BETWEEN c.admittime AND c.first12h_end AND (p.drug LIKE '%pioglitazone%' OR p.drug LIKE '%rosiglitazone%' OR p.drug LIKE '%thiazolidinedione%' OR p.drug LIKE '%tzd%') THEN 1 ELSE 0 END) AS tzd_first12h,

        -- Check for each drug class in final 48h
        MAX(CASE WHEN p.starttime BETWEEN c.final48h_start AND c.dischtime AND p.drug LIKE '%insulin%' THEN 1 ELSE 0 END) AS insulin_final48h,
        MAX(CASE WHEN p.starttime BETWEEN c.final48h_start AND c.dischtime AND (p.drug LIKE '%metformin%' OR p.drug LIKE '%glucophage%') THEN 1 ELSE 0 END) AS metformin_final48h,
        MAX(CASE WHEN p.starttime BETWEEN c.final48h_start AND c.dischtime AND (p.drug LIKE '%glyburide%' OR p.drug LIKE '%glipizide%' OR p.drug LIKE '%glimepiride%' OR p.drug LIKE '%sulfonylurea%') THEN 1 ELSE 0 END) AS sulfonylureas_final48h,
        MAX(CASE WHEN p.starttime BETWEEN c.final48h_start AND c.dischtime AND (p.drug LIKE '%sitagliptin%' OR p.drug LIKE '%saxagliptin%' OR p.drug LIKE '%linagliptin%' OR p.drug LIKE '%alogliptin%' OR p.drug LIKE '%dutogliptin%' OR p.drug LIKE '%gemigliptin%' OR p.drug LIKE '%dpp4%' OR p.drug LIKE '%dpp-4%') THEN 1 ELSE 0 END) AS dpp4_final48h,
        MAX(CASE WHEN p.starttime BETWEEN c.final48h_start AND c.dischtime AND (p.drug LIKE '%canagliflozin%' OR p.drug LIKE '%dapagliflozin%' OR p.drug LIKE '%empagliflozin%' OR p.drug LIKE '%sglt2%' OR p.drug LIKE '%sglt-2%') THEN 1 ELSE 0 END) AS sglt2_final48h,
        MAX(CASE WHEN p.starttime BETWEEN c.final48h_start AND c.dischtime AND (p.drug LIKE '%liraglutide%' OR p.drug LIKE '%dulaglutide%' OR p.drug LIKE '%exenatide%' OR p.drug LIKE '%lixisenatide%' OR p.drug LIKE '%semaglutide%' OR p.drug LIKE '%glp1%' OR p.drug LIKE '%glp-1%') THEN 1 ELSE 0 END) AS glp1_final48h,
        MAX(CASE WHEN p.starttime BETWEEN c.final48h_start AND c.dischtime AND (p.drug LIKE '%pioglitazone%' OR p.drug LIKE '%rosiglitazone%' OR p.drug LIKE '%thiazolidinedione%' OR p.drug LIKE '%tzd%') THEN 1 ELSE 0 END) AS tzd_final48h

    FROM cohort c
    LEFT JOIN `physionet-data.mimiciv_3_1_hosp.prescriptions` p
        ON c.hadm_id = p.hadm_id AND c.subject_id = p.subject_id
    GROUP BY c.hadm_id
)

SELECT 
    'Insulin' AS drug_class,
    AVG(insulin_first12h) * 100 AS initiation_first12h_percent,
    AVG(insulin_final48h) * 100 AS initiation_final48h_percent
FROM drug_classes
UNION ALL
SELECT 
    'Metformin',
    AVG(metformin_first12h) * 100,
    AVG(metformin_final48h) * 100
FROM drug_classes
UNION ALL
SELECT 
    'Sulfonylureas',
    AVG(sulfonylureas_first12h) * 100,
    AVG(sulfonylureas_final48h) * 100
FROM drug_classes
UNION ALL
SELECT 
    'DPP-4',
    AVG(dpp4_first12h) * 100,
    AVG(dpp4_final48h) * 100
FROM drug_classes
UNION ALL
SELECT 
    'SGLT2',
    AVG(sglt2_first12h) * 100,
    AVG(sglt2_final48h) * 100
FROM drug_classes
UNION ALL
SELECT 
    'GLP-1',
    AVG(glp1_first12h) * 100,
    AVG(glp1_final48h) * 100
FROM drug_classes
UNION ALL
SELECT 
    'TZDs',
    AVG(tzd_first12h) * 100,
    AVG(tzd_final48h) * 100
FROM drug_classes
ORDER BY drug_class;