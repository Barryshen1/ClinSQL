WITH diabetes_codes AS (
  SELECT icd_code, icd_version
  FROM `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses`
  WHERE (icd_version = 10 AND SUBSTR(icd_code, 1, 3) = 'E11') -- Type 2 DM
     OR (icd_version = 10 AND icd_code = 'E10') -- Type 1 DM
     OR (icd_version = 9 AND SUBSTR(icd_code, 1, 3) = '250') -- Diabetes mellitus
),
hf_codes AS (
  SELECT icd_code, icd_version
  FROM `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses`
  WHERE (icd_version = 10 AND icd_code IN ('I50.21', 'I50.31', 'I50.41', 'I50.1', 'I50.9'))
     OR (icd_version = 9 AND SUBSTR(icd_code, 1, 3) = '428')
),
eligible_admissions AS (
  SELECT a.hadm_id, a.admittime, a.dischtime
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` p ON a.subject_id = p.subject_id
  WHERE p.gender = 'M'
    AND p.anchor_age BETWEEN 68 AND 78
    AND EXISTS (
      SELECT 1
      FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` di
      JOIN diabetes_codes dc ON di.icd_code = dc.icd_code AND di.icd_version = dc.icd_version
      WHERE di.hadm_id = a.hadm_id
    )
    AND EXISTS (
      SELECT 1
      FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` di
      JOIN hf_codes hc ON di.icd_code = hc.icd_code AND di.icd_version = hc.icd_version
      WHERE di.hadm_id = a.hadm_id
    )
),
drug_classification AS (
  SELECT 
    ea.hadm_id,
    -- Flag if insulin was prescribed in first 24h
    MAX(CASE 
      WHEN p.starttime >= ea.admittime AND p.starttime < DATETIME_ADD(ea.admittime, INTERVAL 1 DAY)
        AND LOWER(p.drug) LIKE '%insulin%' THEN 1 ELSE 0 
    END) AS insulin_first_24h,
    -- Flag if insulin was prescribed in last 24h
    MAX(CASE 
      WHEN p.starttime >= DATETIME_SUB(ea.dischtime, INTERVAL 1 DAY) AND p.starttime <= ea.dischtime
        AND LOWER(p.drug) LIKE '%insulin%' THEN 1 ELSE 0 
    END) AS insulin_last_24h,
    -- Flag if oral agent was prescribed in first 24h
    MAX(CASE 
      WHEN p.starttime >= ea.admittime AND p.starttime < DATETIME_ADD(ea.admittime, INTERVAL 1 DAY)
        AND LOWER(p.drug) NOT LIKE '%insulin%'
        AND LOWER(p.drug) IN (
          'metformin', 'glipizide', 'glyburide', 'glimepiride', 
          'sitagliptin', 'saxagliptin', 'linagliptin', 'pioglitazone', 
          'rosiglitazone', 'acarbose', 'miglitol', 'repaglinide', 
          'nateglinide', 'canagliflozin', 'dapagliflozin', 'empagliflozin', 'ertugliflozin'
        ) THEN 1 ELSE 0 
    END) AS oral_first_24h,
    -- Flag if oral agent was prescribed in last 24h
    MAX(CASE 
      WHEN p.starttime >= DATETIME_SUB(ea.dischtime, INTERVAL 1 DAY) AND p.starttime <= ea.dischtime
        AND LOWER(p.drug) NOT LIKE '%insulin%'
        AND LOWER(p.drug) IN (
          'metformin', 'glipizide', 'glyburide', 'glimepiride', 
          'sitagliptin', 'saxagliptin', 'linagliptin', 'pioglitazone', 
          'rosiglitazone', 'acarbose', 'miglitol', 'repaglinide', 
          'nateglinide', 'canagliflozin', 'dapagliflozin', 'empagliflozin', 'ertugliflozin'
        ) THEN 1 ELSE 0 
    END) AS oral_last_24h
  FROM eligible_admissions ea
  LEFT JOIN `physionet-data.mimiciv_3_1_hosp.prescriptions` p ON ea.hadm_id = p.hadm_id
  GROUP BY ea.hadm_id
),
summary AS (
  SELECT
    AVG(insulin_first_24h) * 100 AS insulin_first_24h_pct,
    AVG(insulin_last_24h) * 100 AS insulin_last_24h_pct,
    AVG(oral_first_24h) * 100 AS oral_first_24h_pct,
    AVG(oral_last_24h) * 100 AS oral_last_24h_pct
  FROM drug_classification
)
SELECT
  insulin_first_24h_pct,
  insulin_last_24h_pct,
  insulin_last_24h_pct - insulin_first_24h_pct AS insulin_diff,
  oral_first_24h_pct,
  oral_last_24h_pct,
  oral_last_24h_pct - oral_first_24h_pct AS oral_diff
FROM summary;