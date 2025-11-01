WITH cohort AS (
    SELECT a.subject_id, a.hadm_id, a.admittime, a.dischtime
    FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
    JOIN `physionet-data.mimiciv_3_1_hosp.patients` p ON a.subject_id = p.subject_id
    WHERE p.gender = 'M'
      AND p.anchor_age BETWEEN 77 AND 87
      AND EXISTS (
          SELECT 1
          FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
          WHERE d.hadm_id = a.hadm_id
            AND (
                (d.icd_version = 9 AND d.icd_code LIKE '250%')
                OR (d.icd_version = 10 AND (d.icd_code LIKE 'E10%' OR d.icd_code LIKE 'E11%' OR d.icd_code LIKE 'E12%' OR d.icd_code LIKE 'E13%' OR d.icd_code LIKE 'E14%'))
            )
      )
      AND EXISTS (
          SELECT 1
          FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
          WHERE d.hadm_id = a.hadm_id
            AND (
                (d.icd_version = 9 AND d.icd_code LIKE '428%')
                OR (d.icd_version = 10 AND d.icd_code LIKE 'I50%')
            )
      )
),
prescriptions_with_class AS (
    SELECT
        c.hadm_id,
        c.admittime,
        c.dischtime,
        p.starttime,
        CASE
            WHEN LOWER(p.drug) LIKE '%insulin%' OR LOWER(p.drug) LIKE '%lantus%' OR LOWER(p.drug) LIKE '%humalog%' OR LOWER(p.drug) LIKE '%novolog%' OR LOWER(p.drug) LIKE '%apidra%' OR LOWER(p.drug) LIKE '%levemir%' OR LOWER(p.drug) LIKE '%toujeo%' OR LOWER(p.drug) LIKE '%basaglar%' OR LOWER(p.drug) LIKE '%metformin%' OR LOWER(p.drug) LIKE '%glipizide%' OR LOWER(p.drug) LIKE '%glyburide%' OR LOWER(p.drug) LIKE '%glimepiride%' OR LOWER(p.drug) LIKE '%sitagliptin%' OR LOWER(p.drug) LIKE '%linagliptin%' OR LOWER(p.drug) LIKE '%alogliptin%' OR LOWER(p.drug) LIKE '%pioglitazone%' OR LOWER(p.drug) LIKE '%rosiglitazone%' OR LOWER(p.drug) LIKE '%exenatide%' OR LOWER(p.drug) LIKE '%liraglutide%' OR LOWER(p.drug) LIKE '%dulaglutide%' OR LOWER(p.drug) LIKE '%semaglutide%' OR LOWER(p.drug) LIKE '%dapagliflozin%' OR LOWER(p.drug) LIKE '%canagliflozin%' OR LOWER(p.drug) LIKE '%empagliflozin%' OR LOWER(p.drug) LIKE '%ertugliflozin%' THEN 'antidiabetic'
            WHEN LOWER(p.drug) LIKE '%metoprolol%' OR LOWER(p.drug) LIKE '%atenolol%' OR LOWER(p.drug) LIKE '%propranolol%' OR LOWER(p.drug) LIKE '%carvedilol%' OR LOWER(p.drug) LIKE '%bisoprolol%' OR LOWER(p.drug) LIKE '%nadolol%' OR LOWER(p.drug) LIKE '%sotalol%' THEN 'beta-blocker'
            WHEN LOWER(p.drug) LIKE '%lisinopril%' OR LOWER(p.drug) LIKE '%enalapril%' OR LOWER(p.drug) LIKE '%ramipril%' OR LOWER(p.drug) LIKE '%captopril%' OR LOWER(p.drug) LIKE '%quinapril%' OR LOWER(p.drug) LIKE '%perindopril%' OR LOWER(p.drug) LIKE '%benazepril%' OR LOWER(p.drug) LIKE '%losartan%' OR LOWER(p.drug) LIKE '%valsartan%' OR LOWER(p.drug) LIKE '%irbesartan%' OR LOWER(p.drug) LIKE '%telmisartan%' OR LOWER(p.drug) LIKE '%candesartan%' OR LOWER(p.drug) LIKE '%olmesartan%' OR (LOWER(p.drug) LIKE '%sacubitril%' AND LOWER(p.drug) LIKE '%valsartan%') THEN 'acei_arb_arni'
            WHEN LOWER(p.drug) LIKE '%furosemide%' OR LOWER(p.drug) LIKE '%bumetanide%' OR LOWER(p.drug) LIKE '%torsemide%' THEN 'loop_diuretic'
            ELSE NULL
        END AS drug_class
    FROM `physionet-data.mimiciv_3_1_hosp.prescriptions` p
    JOIN cohort c ON p.hadm_id = c.hadm_id
    WHERE p.starttime IS NOT NULL
)
SELECT
    drug_class,
    COUNT(DISTINCT CASE WHEN starttime BETWEEN admittime AND admittime + INTERVAL 48 HOUR THEN hadm_id END) * 100.0 / COUNT(DISTINCT hadm_id) AS first_48h_rate,
    COUNT(DISTINCT CASE WHEN starttime BETWEEN dischtime - INTERVAL 12 HOUR AND dischtime THEN hadm_id END) * 100.0 / COUNT(DISTINCT hadm_id) AS last_12h_rate,
    (COUNT(DISTINCT CASE WHEN starttime BETWEEN dischtime - INTERVAL 12 HOUR AND dischtime THEN hadm_id END) - COUNT(DISTINCT CASE WHEN starttime BETWEEN admittime AND admittime + INTERVAL 48 HOUR THEN hadm_id END)) * 100.0 / COUNT(DISTINCT hadm_id) AS net_change
FROM prescriptions_with_class
WHERE drug_class IS NOT NULL
GROUP BY drug_class;