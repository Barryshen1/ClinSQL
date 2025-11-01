WITH cohort AS (
    SELECT 
        adm.subject_id, 
        adm.hadm_id, 
        adm.admittime, 
        adm.dischtime
    FROM `physionet-data.mimiciv_3_1_hosp.admissions` adm
    INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` pat
        ON adm.subject_id = pat.subject_id
    WHERE pat.gender = 'M'
        AND pat.anchor_age BETWEEN 77 AND 87
        AND adm.hadm_id IN (
            SELECT hadm_id FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` 
            WHERE icd_code LIKE 'I50%' AND icd_version = 10
        )
        AND adm.hadm_id IN (
            SELECT hadm_id FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` 
            WHERE icd_code LIKE 'E1[0-4]%' AND icd_version = 10
        )
),

drug_classes AS (
    SELECT 
        hadm_id,
        CASE 
            WHEN LOWER(drug) LIKE '%insulin%' OR LOWER(drug) LIKE '%metformin%' OR LOWER(drug) LIKE '%glipizide%' 
                 OR LOWER(drug) LIKE '%glyburide%' OR LOWER(drug) LIKE '%glimepiride%' OR LOWER(drug) LIKE '%pioglitazone%'
                 OR LOWER(drug) LIKE '%sitagliptin%' OR LOWER(drug) LIKE '%saxagliptin%' OR LOWER(drug) LIKE '%dapagliflozin%'
                 OR LOWER(drug) LIKE '%empagliflozin%' OR LOWER(drug) LIKE '%canagliflozin%' OR LOWER(drug) LIKE '%linagliptin%'
                 OR LOWER(drug) LIKE '%alogliptin%' OR LOWER(drug) LIKE '%repaglinide%' OR LOWER(drug) LIKE '%nateglinide%'
                 THEN 'antidiabetic'
            WHEN LOWER(drug) LIKE '%lol%' OR LOWER(drug) LIKE '%carvedilol%' OR LOWER(drug) LIKE '%sotalol%'
                 THEN 'beta_blocker'
            WHEN LOWER(drug) LIKE '%pril%' OR LOWER(drug) LIKE '%sartan%' OR LOWER(drug) LIKE '%sacubitril%'
                 OR LOWER(drug) LIKE '%valsartan%' OR LOWER(drug) LIKE '%losartan%' OR LOWER(drug) LIKE '%irbesartan%'
                 OR LOWER(drug) LIKE '%olmesartan%' OR LOWER(drug) LIKE '%candesartan%' OR LOWER(drug) LIKE '%eprosartan%'
                 OR LOWER(drug) LIKE '%azilsartan%' OR LOWER(drug) LIKE '%entresto%' 
                 THEN 'acei_arb_arni'
            WHEN LOWER(drug) LIKE '%furosemide%' OR LOWER(drug) LIKE '%bumetanide%' OR LOWER(drug) LIKE '%torsemide%'
                 THEN 'loop_diuretic'
            ELSE NULL
        END AS drug_class,
        MIN(starttime) AS first_starttime
    FROM `physionet-data.mimiciv_3_1_hosp.prescriptions` rx
    INNER JOIN cohort c
        ON rx.hadm_id = c.hadm_id
    GROUP BY hadm_id, drug_class
    HAVING drug_class IS NOT NULL
),

initiations AS (
    SELECT 
        c.hadm_id,  -- Explicit alias to resolve ambiguity
        dc.drug_class,
        MAX(CASE WHEN dc.first_starttime BETWEEN c.admittime AND DATETIME_ADD(c.admittime, INTERVAL 48 HOUR) THEN 1 ELSE 0 END) AS initiated_first_48h,
        MAX(CASE WHEN dc.first_starttime BETWEEN DATETIME_SUB(c.dischtime, INTERVAL 12 HOUR) AND c.dischtime THEN 1 ELSE 0 END) AS initiated_last_12h
    FROM cohort c
    LEFT JOIN drug_classes dc
        ON c.hadm_id = dc.hadm_id
    GROUP BY c.hadm_id, dc.drug_class
),

aggregated AS (
    SELECT 
        drug_class,
        COUNT(*) AS total_patients,
        SUM(initiated_first_48h) AS count_first_48h,
        SUM(initiated_last_12h) AS count_last_12h
    FROM initiations
    GROUP BY drug_class
)

SELECT 
    drug_class,
    ROUND(100.0 * count_first_48h / total_patients, 2) AS first_48h_rate,
    ROUND(100.0 * count_last_12h / total_patients, 2) AS last_12h_rate,
    ROUND(100.0 * count_last_12h / total_patients - 100.0 * count_first_48h / total_patients, 2) AS net_change
FROM aggregated
ORDER BY drug_class;