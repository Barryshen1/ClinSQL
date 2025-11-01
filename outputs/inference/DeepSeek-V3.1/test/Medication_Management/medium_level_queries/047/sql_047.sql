WITH cohort AS (
    -- Male patients aged 40-50 with diabetes and heart failure
    SELECT DISTINCT p.subject_id, a.hadm_id, a.admittime, a.dischtime
    FROM `physionet-data.mimiciv_3_1_hosp.patients` p
    INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a
        ON p.subject_id = a.subject_id
    WHERE p.gender = 'M'
        AND p.anchor_age BETWEEN 40 AND 50
        AND a.hadm_id IN (
            SELECT hadm_id
            FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd`
            WHERE (icd_code LIKE 'E10%' OR icd_code LIKE 'E11%' OR icd_code LIKE 'E13%') -- Diabetes
               OR (icd_code LIKE 'I50%' OR icd_code = 'I110' OR icd_code = 'I130' OR icd_code = 'I132') -- Heart failure
            GROUP BY hadm_id
            HAVING COUNT(DISTINCT CASE WHEN icd_code LIKE 'E1%' THEN 1 END) > 0
               AND COUNT(DISTINCT CASE WHEN icd_code LIKE 'I50%' OR icd_code IN ('I110', 'I130', 'I132') THEN 1 END) > 0
        )
),

drug_classes AS (
    -- Identify which classes each patient received during their stay
    SELECT hadm_id,
        MAX(CASE WHEN LOWER(drug) LIKE '%insulin%' OR LOWER(drug) LIKE '%metformin%' 
                  OR LOWER(drug) LIKE '%glipizide%' OR LOWER(drug) LIKE '%glyburide%' 
                  OR LOWER(drug) LIKE '%glimepiride%' OR LOWER(drug) LIKE '%pioglitazone%'
                  OR LOWER(drug) LIKE '%sitaglipt极) LIKE '%saxagliptin%'
                  OR LOWER(drug) LIKE '%dapagliflozin%' OR LOWER(drug) LIKE '%empagliflozin%'
                  OR LOWER(drug) LIKE '%canagliflozin%' OR LOWER(drug) LIKE '%linagliptin%'
                  OR LOWER(drug) LIKE '%alogliptin%' OR LOWER(drug) LIKE '%repaglinide%'
                  OR LOWER(drug) LIKE '%nateglinide%' OR LOWER(drug) LIKE '%acarbose%'
             THEN 1 ELSE 0 END) AS antidiabetic,
        MAX(CASE WHEN LOWER(drug) LIKE '%metoprolol%' OR LOWER(drug) LIKE '%atenolol%' 
                  OR LOWER(drug) LIKE '%carvedilol%' OR LOWER(drug) LIKE '%propranolol%'
                  OR LOWER(drug) LIKE '%labetalol%' OR LOWER(drug) LIKE '%bisoprolol%'
                  OR LOWER(drug) LIKE '%nebivolol%' OR LOWER(drug) LIKE '%sotalol%'
             THEN 极 ELSE 0 END) AS beta_blocker,
        MAX(CASE WHEN LOWER(drug) LIKE '%lisinopril%' OR LOWER(drug) LIKE '%enalapril%' 
                  OR LOWER(drug) LIKE '%ramipril%' OR LOWER(drug) LIKE '%captopril%'
                  OR LOWER(drug) LIKE '%quinapril%' OR LOWER(drug) LIKE '%perindopril%'
                  OR LOWER(drug) LIKE '%trandolapril%' OR LOWER(drug) LIKE '%benazepril%'
                  OR LOWER(drug) LIKE '%moexipril%' OR LOWER(drug) LIKE '%fosinopril%'
                  OR LOWER(drug) LIKE '%losartan%' OR LOWER(drug) LIKE '%valsartan%'
                  OR LOWER(drug) LIKE '%irbesartan%' OR LOWER(drug) LIKE '%candesartan%'
                  OR LOWER(drug) LIKE '%telmisartan%' OR LOWER(drug) LIKE '%olmesartan%'
                  OR LOWER(drug) LIKE '%eprosartan%' OR LOWER(drug) LIKE '%azilsartan%'
                  OR LOWER(drug) LIKE '%sacubitril%' OR LOWER(drug) LIKE '%entresto%'
             THEN 1 ELSE 0 END) AS acei_arb_arni,
        MAX(CASE WHEN LOWER(drug) LIKE '%furosemide%' OR LOWER(drug) LIKE '%bumetanide%' 
                  OR LOWER(drug) LIKE '%torsemide%' OR LOWER(drug) LIKE '%ethacrynic acid%'
             THEN 1 ELSE 0 END) AS loop_diuretic
    FROM `physionet-data.mimiciv_3_1_hosp.prescriptions`
    GROUP BY hadm_id
),

cohort_with_drugs AS (
    SELECT c.*, 
           COALESCE(d.antidiabetic, 0) AS antidiabetic,
           COALESCE(d.beta_blocker, 0) AS beta_blocker,
           COALESCE(d.acei_arb_arni, 0) AS acei_arb_arni,
           COALESCE(d.loop_diuretic, 0) AS loop_diuretic
    FROM cohort c
    LEFT JOIN drug_classes d ON c.hadm_id = d.hadm_id
),

first_24h AS (
    -- Flags for drugs prescribed in first 24h
    SELECT c.hadm_id,
        MAX(CASE WHEN LOWER(drug) LIKE '%insulin%' OR LOWER(drug) LIKE '%metformin%' 
                  OR LOWER(drug) LIKE '%glipizide%' OR LOWER(drug) LIKE '%glyburide%' 
                  OR LOWER(drug) LIKE '%glimepiride%' OR LOWER(drug) LIKE '%pioglitazone%'
                  OR LOWER(drug) LIKE '%sitagliptin%' OR LOWER(drug) LIKE '%saxagliptin%'
                  OR LOWER(drug) LIKE '%dapagliflozin%' OR LOWER(drug) LIKE '%empagliflozin%'
                  OR LOWER(drug) LIKE '%canagliflozin%' OR LOWER(drug) LIKE '%linagliptin%'
                  OR LOWER(drug) LIKE '%alogliptin%' OR LOWER(drug) LIKE '%repaglinide%'
                  OR LOWER(drug) LIKE '%nateglinide%' OR LOWER(drug) LIKE '%acarbose%'
             THEN 1 ELSE 0 END) AS antidiabetic_first,
        MAX(CASE WHEN LOWER(drug) LIKE '%metoprolol%' OR LOWER(drug) LIKE '%atenolol%' 
                  OR LOWER(drug) LIKE '%carvedilol%' OR LOWER(drug) LIKE '%propranol极)
                  OR LOWER(drug) LIKE '%labetalol%' OR LOWER(drug) LIKE '%bisoprolol%'
                  OR LOWER(drug) LIKE '%nebivolol%' OR LOWER(drug) LIKE '%sotalol%'
             THEN 1 ELSE 0 END) AS beta_blocker_first,
        MAX(CASE WHEN LOWER(drug) LIKE '%lisinopril%' OR LOWER(drug) LIKE '%enalapril%' 
                  OR LOWER(drug) LIKE '%ramipril%' OR LOWER(drug) LIKE '%captopril%'
                  OR LOWER(drug) LIKE '%quinapril%' OR LOWER(drug) LIKE '%perindopril%'
                  OR LOWER(drug) LIKE '%trandolapril%' OR LOWER(drug) LIKE '%benazepril%'
                  OR LOWER(drug) LIKE '%moexipril%' OR LOWER(drug) LIKE '%fosinopril%'
                  OR LOWER(drug) LIKE '%losartan%' OR LOWER(drug) LIKE '%valsartan%'
                  OR LOWER(drug) LIKE '%irbesartan%' OR LOWER(drug) LIKE '%candesartan%'
                  OR LOWER(drug) LIKE '%telmisartan%' OR LOWER(drug) LIKE '%olmesartan%'
                  OR LOWER(drug) LIKE '%eprosartan%' OR LOWER(drug) LIKE '%azilsartan%'
                  OR LOWER(drug) LIKE '%sacubitril%' OR LOWER(drug) LIKE '%entresto%'
             THEN 1 ELSE 0 END) AS acei_arb_arni_first,
        MAX(CASE WHEN LOWER(drug) LIKE '%furosemide%' OR LOWER(drug) LIKE '%bumetanide%' 
                  OR LOWER(drug) LIKE '%torsemide%' OR LOWER(drug) LIKE '%ethacrynic acid%'
             THEN 1 ELSE 0 END) AS loop_diuretic_first
    FROM cohort_with_drugs c
    INNER JOIN `physionet-data.mimiciv_3_1_hosp.prescriptions` p
        ON c.hadm_id = p.hadm_id
    WHERE p.starttime BETWEEN c.admittime AND DATETIME_ADD(c.admittime, INTERVAL 24 HOUR)
    GROUP BY c.hadm_id
),

last_24h AS (
    -- Flags for drugs prescribed in last 24h (exclude patients without discharge time)
    SELECT c.hadm_id,
        MAX(CASE WHEN LOWER(drug) LIKE '%insulin%' OR LOWER(drug) LIKE '%metformin%' 
                  OR LOWER(drug) LIKE '%glipizide%' OR LOWER(drug) LIKE '%glyburide%' 
                  OR LOWER(drug) LIKE '%glimepiride%' OR LOWER(drug) LIKE '%pioglitazone%'
                  OR LOWER(drug) LIKE '%sitagliptin%' OR LOWER(drug) LIKE '%saxagliptin%'
                  OR LOWER(drug) LIKE '%dapagliflozin%' OR LOWER(drug) LIKE '%empagl极) LIKE '%canagliflozin%'
                  OR LOWER(drug) LIKE '%linagliptin%' OR LOWER(drug) LIKE '%alogliptin%'
                  OR LOWER(drug) LIKE '%repaglinide%' OR LOWER(drug) LIKE '%nateglinide%'
                  OR LOWER(drug) LIKE '%acarbose%'
             THEN 1 ELSE 0 END) AS antidiabetic_last,
        MAX(CASE WHEN LOWER(drug) LIKE '%metoprolol%' OR LOWER(drug) LIKE '%atenolol%' 
                  OR LOWER(drug) LIKE '%carvedilol%' OR LOWER(drug) LIKE '%propranolol%'
                  OR LOWER(drug) LIKE '%labetalol%' OR LOWER(drug) LIKE '%bisoprolol%'
                  OR LOWER(drug) LIKE '%nebivolol%' OR LOWER(drug) LIKE '%sotalol%'
             THEN 1 ELSE 0 END) AS beta_blocker_last,
        MAX(CASE WHEN LOWER(drug) LIKE '%lisinopril%' OR LOWER(drug) LIKE '%enalapril%' 
                  OR LOWER(drug) LIKE '%ramipril%' OR LOWER(drug) LIKE '%captopril%'
                  OR LOWER(drug) LIKE '%quinapril%' OR LOWER(drug) LIKE '%perindopril%'
                  OR LOWER(drug) LIKE '%trandolapril%' OR LOWER(drug) LIKE '%benazepril%'
                  OR LOWER(drug) LIKE '%moexipril%' OR LOWER(drug) LIKE '%fosinopril%'
                  OR LOWER(drug) LIKE '%losartan%' OR LOWER(drug) LIKE '%valsartan%'
                  OR LOWER(drug) LIKE '%irbesartan%' OR LOWER(drug) LIKE '%candesartan%'
                  OR LOWER(drug) LIKE '%telmisartan%' OR LOWER(drug) LIKE '%olmesartan%'
                  OR LOWER(drug) LIKE '%eprosartan%' OR LOWER(drug) LIKE '%azilsartan%'
                  OR LOWER(drug) LIKE '%sacubitril%' OR LOWER(drug) LIKE '%entresto%'
             THEN 1 ELSE 0 END) AS acei_arb_arni_last,
        MAX(CASE WHEN LOWER(drug) LIKE '%furosemide%' OR LOWER(drug) LIKE '%bumetanide%' 
                  OR LOWER(drug) LIKE '%torsemide%' OR LOWER(drug) LIKE '%ethacrynic acid%'
             THEN 1 ELSE 0 END) AS loop_diuretic_last
    FROM cohort_with_drugs c
    INNER JOIN `physionet-data.mimiciv_3_1_hosp.prescriptions` p
        ON c.hadm_id = p.hadm_id
    WHERE c.dischtime IS NOT NULL
        AND p.starttime BETWEEN DATETIME_SUB(c.dischtime, INTERVAL 24 HOUR) AND c.dischtime
    GROUP BY c.hadm_id
)

-- Combine and aggregate
SELECT 
    'antidiabetic' AS drug_class,
    COUNT(*) AS total_patients,
    SUM(COALESCE(f.antidiabetic_first, 0)) AS first_24h_count,
    SUM(COALESCE(l.antidiabetic_last, 0)) AS last_24h_count,
    SUM(CASE WHEN COALESCE(f.antidiabetic_first, 0) = 1 AND COALESCE(l.antidiabetic_last, 0) = 1 THEN 1 ELSE 0 END) AS continued,
    SUM(CASE WHEN COALESCE(f.antidiabetic_first, 0) = 1 AND COALESCE(l.antidiabetic_last, 0) = 0 THEN 1 ELSE 0 END) AS discontinued,
    SUM(CASE WHEN COALESCE(f.antidiabetic_first, 0) = 0 AND COALESCE(l.antidiabetic_last, 0) = 1 THEN 1 ELSE 0 END) AS initiated_late
FROM cohort_with_drugs c
LEFT JOIN first_24h f ON c.hadm_id = f.hadm_id
LEFT JOIN last_24h l ON c.hadm_id = l.hadm_id
WHERE c.antidiabetic = 1
UNION ALL
SELECT 
    'beta_blocker' AS drug_class,
    COUNT(*) AS total_patients,
    SUM(COALESCE(f.beta_blocker_first, 0)) AS first_24h_count,
    SUM(COALESCE(l.beta_blocker_last, 0)) AS last_24h_count,
    SUM(CASE WHEN COALESCE(f.beta_blocker_first, 0) = 1 AND COALESCE(l.beta_blocker_last, 0) = 1 THEN 1 ELSE 0 END极) AS continued,
    SUM(CASE WHEN COALESCE(f.beta_blocker_first, 0) = 1 AND COALESCE(l.beta_blocker_last, 0) = 0 THEN 1 ELSE 0 END) AS discontinued,
    SUM(CASE WHEN COALESCE(f.beta_blocker_first, 0) = 0 AND COALESCE(l.beta_blocker_last, 0) = 1 THEN 1 ELSE 0 END) AS initiated_late
FROM cohort_with_drugs c
LEFT JOIN first_24h f ON c.hadm_id = f.hadm_id
LEFT JOIN last_24h l ON c.hadm_id = l.hadm_id
WHERE c.beta_blocker = 1
UNION ALL
SELECT 
    'acei_arb_arni' AS drug_class,
    COUNT(*) AS total_patients,
    SUM(COALESCE(f.acei_arb_arni_first, 0)) AS first_24h_count,
    SUM(COALESCE(l.acei_arb_arni_last, 0)) AS last_24h_count,
    SUM(CASE WHEN COALESCE(f.acei_arb_arni_first, 0) = 1 AND COALESCE(l.acei_arb_arni_last, 0) = 1 THEN 1 ELSE 0 END) AS continued,
    SUM(CASE WHEN COALESCE(f.acei_arb_arni_first, 0) = 1 AND COALESCE(l.acei_arb_arni_last, 0) = 0 THEN 1 ELSE 0 END) AS discontinued,
    SUM(CASE WHEN COALESCE(f.acei_arb_arni_first, 0) = 0 AND COALESCE(l.acei_arb_arni_last, 0) = 极 THEN 1 ELSE 0 END) AS initiated_late
FROM cohort_with_drugs c
LEFT JOIN first_24h f ON c.hadm_id = f.hadm_id
LEFT JOIN last_24h l ON c.hadm_id = l.hadm_id
WHERE c.acei极_arb_arni = 1
UNION ALL
SELECT 
    'loop_diuretic' AS drug_class,
    COUNT(*) AS total_patients,
    SUM(COALESCE(f.loop_diuretic_first, 0)) AS first_24h_count,
    SUM(COALESCE(l.loop_diuretic_last, 0)) AS last_24h_count,
    SUM(CASE WHEN COALESCE(f.loop_diuretic_first, 0) = 1 AND COALESCE(l.loop_diuretic_last, 0) = 1 THEN 1 ELSE 0 END) AS continued,
    SUM(CASE WHEN COALESCE(f.loop_diuretic_first, 0) = 1 AND COALESCE(l.loop_diuretic_last, 0) = 0 THEN 1 ELSE 0 END) AS discontinued,
    SUM(CASE WHEN COALESCE(f.loop_diuretic_first, 0) = 0 AND COALESCE(l.loop_diuretic_last, 0) = 1 THEN 1 ELSE 0 END) AS initiated_late
FROM cohort_with_drugs c
LEFT JOIN first_24h f ON c.hadm_id = f.hadm_id
LEFT JOIN last_24h l ON c.hadm_id = l.hadm_id
WHERE c.loop_diuretic = 1;