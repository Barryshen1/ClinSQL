WITH cohort AS (
  SELECT DISTINCT
    a.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON a.subject_id = p.subject_id
  JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d1
    ON a.hadm_id = d1.hadm_id
  JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` d1d
    ON d1.icd_code = d1d.icd_code AND d1.icd_version = d1d.icd_version
  JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d2
    ON a.hadm_id = d2.hadm_id
  JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` d2d
    ON d2.icd_code = d2d.icd_code AND d2.icd_version = d2d.icd_version
  WHERE p.anchor_age BETWEEN 45 AND 55
    AND p.gender = 'M'
    AND (
      LOWER(d1d.long_title) LIKE '%type 2 diabetes%' 
      OR LOWER(d1d.long_title) LIKE '%diabetes mellitus, type 2%' 
      OR LOWER(d1d.long_title) LIKE '%diabetes mellitus type 2%' 
      OR d1d.icd_code LIKE 'E11%' 
      OR d1d.icd_code LIKE '250.%'
    )
    AND (
      LOWER(d2d.long_title) LIKE '%heart failure%' 
      OR d2d.icd_code LIKE 'I50%' 
      OR d2d.icd_code LIKE '428.%'
    )
    AND a.dischtime >= a.admittime + INTERVAL '48 hours'
),
medications AS (
  SELECT
    p.hadm_id,
    p.starttime,
    LOWER(p.drug) AS drug
  FROM `physionet-data.mimiciv_3_1_hosp.prescriptions` p
  INNER JOIN cohort c ON p.hadm_id = c.hadm_id
  WHERE p.starttime >= c.admittime
    AND p.starttime <= c.dischtime
),
insulin_oral AS (
  SELECT
    m.hadm_id,
    m.starttime,
    CASE
      WHEN m.drug LIKE '%insulin%' OR m.drug IN ('lispro', 'glargine', 'detemir', 'degludec', 'aspart', 'regular', 'nph', 'ultralente', 'lente')
        THEN 'insulin'
      WHEN m.drug IN ('metformin', 'glipizide', 'glyburide', 'gliclazide', 'glimepiride', 'sitagliptin', 'saxagliptin', 'linagliptin', 'alogliptin', 'empagliflozin', 'canagliflozin', 'dapagliflozin', 'pioglitazone', 'rosiglitazone', 'repaglinide', 'nateglinide', 'acarbose', 'miglitol', 'chlorpropamide', 'tolbutamide', 'acetohexamide', 'tolazamide')
        THEN 'oral'
      ELSE NULL
    END AS drug_class
  FROM medications m
  WHERE m.drug LIKE '%insulin%' OR m.drug IN ('lispro', 'glargine', 'detemir', 'degludec', 'aspart', 'regular', 'nph', 'ultralente', 'lente', 'metformin', 'glipizide', 'glyburide', 'gliclazide', 'glimepiride', 'sitagliptin', 'saxagliptin', 'linagliptin', 'alogliptin', 'empagliflozin', 'canagliflozin', 'dapagliflozin', 'pioglitazone', 'rosiglitazone', 'repaglinide', 'nateglinide', 'acarbose', 'miglitol', 'chlorpropamide', 'tolbutamide', 'acetohexamide', 'tolazamide')
),
first_48h AS (
  SELECT
    SUM(CASE WHEN io.drug_class = 'insulin' THEN 1 ELSE 0 END) AS insulin_count,
    SUM(CASE WHEN io.drug_class = 'oral' THEN 1 ELSE 0 END) AS oral_count
  FROM insulin_oral io
  JOIN cohort c ON io.hadm_id = c.hadm_id
  WHERE io.starttime >= c.admittime
    AND io.starttime <= c.admittime + INTERVAL '48 hours'
),
final_24h AS (
  SELECT
    SUM(CASE WHEN io.drug_class = 'insulin' THEN 1 ELSE 0 END) AS insulin_count,
    SUM(CASE WHEN io.drug_class = 'oral' THEN 1 ELSE 0 END) AS oral_count
  FROM insulin_oral io
  JOIN cohort c ON io.hadm_id = c.hadm_id
  WHERE io.starttime >= c.dischtime - INTERVAL '24 hours'
    AND io.starttime <= c.dischtime
)
SELECT 'first_48h' AS window,
       ROUND(100.0 * insulin_count / (insulin_count + oral_count), 2) AS percentage
FROM first_48h
WHERE insulin_count + oral_count > 0
UNION ALL
SELECT 'final_24h' AS window,
       ROUND(100.0 * insulin_count / (insulin_count + oral_count), 2) AS percentage
FROM final_24h
WHERE insulin_count + oral_count > 0;