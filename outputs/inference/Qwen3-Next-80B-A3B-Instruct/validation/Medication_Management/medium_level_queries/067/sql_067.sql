WITH cohort AS (
  SELECT DISTINCT p.subject_id, p.anchor_age, p.gender, a.hadm_id, a.admittime, a.dischtime
  FROM physionet-data.mimiciv_3_1_hosp.patients p
  INNER JOIN physionet-data.mimiciv_3_1_hosp.admissions a
    ON p.subject_id = a.subject_id
  INNER JOIN physionet-data.mimiciv_3_1_hosp.diagnoses_icd d1
    ON a.hadm_id = d1.hadm_id
  INNER JOIN physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses d1d
    ON d1.icd_code = d1d.icd_code AND d1.icd_version = d1d.icd_version
  INNER JOIN physionet-data.mimiciv_3_1_hosp.diagnoses_icd d2
    ON a.hadm_id = d2.hadm_id
  INNER JOIN physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses d2d
    ON d2.icd_code = d2d.icd_code AND d2.icd_version = d2d.icd_version
  WHERE p.gender = 'M'
    AND p.anchor_age BETWEEN 64 AND 74
    AND (
      (d1d.long_title LIKE '%diabetes%' OR d1.icd_code LIKE 'E1%' OR d1.icd_code LIKE '250%')
      AND
      (d2d.long_title LIKE '%heart failure%' OR d2.icd_code LIKE 'I50%' OR d2.icd_code LIKE '428%')
    )
),

meds AS (
  SELECT
    c.subject_id,
    c.hadm_id,
    c.admittime,
    c.dischtime,
    p.drug,
    p.starttime,
    CASE
      WHEN LOWER(p.drug) LIKE '%insulin%' OR LOWER(p.drug) LIKE '%humalog%' OR LOWER(p.drug) LIKE '%novolog%' OR LOWER(p.drug) LIKE '%lantus%' OR LOWER(p.drug) LIKE '%glargine%' OR LOWER(p.drug) LIKE '%lispro%' OR LOWER(p.drug) LIKE '%detemir%' OR LOWER(p.drug) LIKE '%aspart%' OR LOWER(p.drug) LIKE '%nph%' THEN 'insulin'
      WHEN LOWER(p.drug) LIKE '%metformin%' OR LOWER(p.drug) LIKE '%glucophage%' THEN 'metformin'
      WHEN LOWER(p.drug) LIKE '%glipizide%' OR LOWER(p.drug) LIKE '%glyburide%' OR LOWER(p.drug) LIKE '%glibenclamide%' OR LOWER(p.drug) LIKE '%glimepiride%' THEN 'sulfonylureas'
      WHEN LOWER(p.drug) LIKE '%sitagliptin%' OR LOWER(p.drug) LIKE '%saxagliptin%' OR LOWER(p.drug) LIKE '%linagliptin%' OR LOWER(p.drug) LIKE '%alogliptin%' THEN 'dpp4'
      WHEN LOWER(p.drug) LIKE '%empagliflozin%' OR LOWER(p.drug) LIKE '%dapagliflozin%' OR LOWER(p.drug) LIKE '%canagliflozin%' THEN 'sglt2'
      WHEN LOWER(p.drug) LIKE '%liraglutide%' OR LOWER(p.drug) LIKE '%semaglutide%' OR LOWER(p.drug) LIKE '%exenatide%' OR LOWER(p.drug) LIKE '%dulaglutide%' THEN 'glp1'
      WHEN LOWER(p.drug) LIKE '%pioglitazone%' OR LOWER(p.drug) LIKE '%rosiglitazone%' THEN 'tzds'
      ELSE NULL
    END AS drug_class
  FROM cohort c
  INNER JOIN physionet-data.mimiciv_3_1_hosp.prescriptions p
    ON c.hadm_id = p.hadm_id
  WHERE p.starttime IS NOT NULL
    AND p.starttime >= c.admittime
    AND p.starttime <= c.dischtime
),

class_counts AS (
  SELECT
    drug_class,
    SUM(CASE WHEN starttime BETWEEN admittime AND TIMESTAMP_ADD(admittime, INTERVAL 12 HOUR) THEN 1 ELSE 0 END) AS first12h_initiators,
    SUM(CASE WHEN starttime BETWEEN TIMESTAMP_SUB(dischtime, INTERVAL 48 HOUR) AND dischtime THEN 1 ELSE 0 END) AS final48h_initiators
  FROM meds
  WHERE drug_class IS NOT NULL
  GROUP BY drug_class
),

total_cohort AS (
  SELECT COUNT(*) AS total_patients FROM cohort
)

SELECT
  cc.drug_class,
  ROUND(100.0 * cc.first12h_initiators / tc.total_patients, 2) AS first12h_percentage,
  ROUND(100.0 * cc.final48h_initiators / tc.total_patients, 2) AS final48h_percentage
FROM class_counts cc
CROSS JOIN total_cohort tc
ORDER BY cc.drug_class;