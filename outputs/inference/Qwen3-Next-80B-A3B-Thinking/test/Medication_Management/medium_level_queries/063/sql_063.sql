WITH eligible_admissions AS (
  SELECT a.hadm_id, a.admittime, a.dischtime
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` p ON a.subject_id = p.subject_id
  WHERE p.gender = 'M'
    AND (p.anchor_age + EXTRACT(YEAR FROM a.admittime) - p.anchor_year) BETWEEN 45 AND 55
    AND EXISTS (
      SELECT 1
      FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
      WHERE d.hadm_id = a.hadm_id
        AND (
          (d.icd_version = 9 AND d.icd_code LIKE '250%') OR
          (d.icd_version = 10 AND d.icd_code LIKE 'E1%')
        )
    )
    AND EXISTS (
      SELECT 1
      FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
      WHERE d.hadm_id = a.hadm_id
        AND (
          (d.icd_version = 9 AND d.icd_code LIKE '428%') OR
          (d.icd_version = 10 AND d.icd_code LIKE 'I50%')
        )
    )
),
prescription_flags AS (
  SELECT
    a.hadm_id,
    MAX(CASE WHEN p.drug LIKE '%Insulin%' AND p.starttime BETWEEN a.admittime AND a.admittime + INTERVAL 12 HOUR THEN 1 ELSE 0 END) AS insulin_first_12h,
    MAX(CASE WHEN p.drug LIKE '%Insulin%' AND p.starttime BETWEEN a.dischtime - INTERVAL 72 HOUR AND a.dischtime THEN 1 ELSE 0 END) AS insulin_final_72h,
    MAX(CASE WHEN p.drug_type = 'oral' AND (
      p.drug LIKE '%Metformin%' OR
      p.drug LIKE '%Glipizide%' OR
      p.drug LIKE '%Glyburide%' OR
      p.drug LIKE '%Pioglitazone%' OR
      p.drug LIKE '%Rosiglitazone%' OR
      p.drug LIKE '%Sitagliptin%' OR
      p.drug LIKE '%Empagliflozin%' OR
      p.drug LIKE '%Dapagliflozin%' OR
      p.drug LIKE '%Canagliflozin%' OR
      p.drug LIKE '%Linagliptin%' OR
      p.drug LIKE '%Alogliptin%' OR
      p.drug LIKE '%Saxagliptin%' OR
      p.drug LIKE '%Tolbutamide%' OR
      p.drug LIKE '%Chlorpropamide%' OR
      p.drug LIKE '%Acetohexamide%' OR
      p.drug LIKE '%Tolazamide%' OR
      p.drug LIKE '%Glucophage%' OR
      p.drug LIKE '%Actos%' OR
      p.drug LIKE '%Avandia%' OR
      p.drug LIKE '%Januvia%' OR
      p.drug LIKE '%Jardiance%' OR
      p.drug LIKE '%Farxiga%' OR
      p.drug LIKE '%Invokana%' OR
      p.drug LIKE '%Tradjenta%' OR
      p.drug LIKE '%Onglyza%' OR
      p.drug LIKE '%Kombiglyze%' OR
      p.drug LIKE '%Xigduo%'
    ) AND p.starttime BETWEEN a.admittime AND a.admittime + INTERVAL 12 HOUR THEN 1 ELSE 0 END) AS oral_first_12h,
    MAX(CASE WHEN p.drug_type = 'oral' AND (
      p.drug LIKE '%Metformin%' OR
      p.drug LIKE '%Glipizide%' OR
      p.drug LIKE '%Glyburide%' OR
      p.drug LIKE '%Pioglitazone%' OR
      p.drug LIKE '%Rosiglitazone%' OR
      p.drug LIKE '%Sitagliptin%' OR
      p.drug LIKE '%Empagliflozin%' OR
      p.drug LIKE '%Dapagliflozin%' OR
      p.drug LIKE '%Canagliflozin%' OR
      p.drug LIKE '%Linagliptin%' OR
      p.drug LIKE '%Alogliptin%' OR
      p.drug LIKE '%Saxagliptin%' OR
      p.drug LIKE '%Tolbutamide%' OR
      p.drug LIKE '%Chlorpropamide%' OR
      p.drug LIKE '%Acetohexamide%' OR
      p.drug LIKE '%Tolazamide%' OR
      p.drug LIKE '%Glucophage%' OR
      p.drug LIKE '%Actos%' OR
      p.drug LIKE '%Avandia%' OR
      p.drug LIKE '%Januvia%' OR
      p.drug LIKE '%Jardiance%' OR
      p.drug LIKE '%Farxiga%' OR
      p.drug LIKE '%Invokana%' OR
      p.drug LIKE '%Tradjenta%' OR
      p.drug LIKE '%Onglyza%' OR
      p.drug LIKE '%Kombiglyze%' OR
      p.drug LIKE '%Xigduo%'
    ) AND p.starttime BETWEEN a.dischtime - INTERVAL 72 HOUR AND a.dischtime THEN 1 ELSE 0 END) AS oral_final_72h
  FROM eligible_admissions a
  LEFT JOIN `physionet-data.mimiciv_3_1_hosp.prescriptions` p ON a.hadm_id = p.hadm_id
  GROUP BY a.hadm_id
)
SELECT
  'Insulin' AS drug,
  AVG(insulin_first_12h) AS rate_first_12h,
  AVG(insulin_final_72h) AS rate_final_72h,
  AVG(insulin_first_12h) - AVG(insulin_final_72h) AS pp_difference
FROM prescription_flags
UNION ALL
SELECT
  'Oral Antidiabetics' AS drug,
  AVG(oral_first_12h) AS rate_first_12h,
  AVG(oral_final_72h) AS rate_final_72h,
  AVG(oral_first_12h) - AVG(oral_final_72h) AS pp_difference
FROM prescription_flags;