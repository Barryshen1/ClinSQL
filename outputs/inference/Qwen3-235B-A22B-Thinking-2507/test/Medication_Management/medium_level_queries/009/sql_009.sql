WITH cohort AS (
  SELECT 
    a.hadm_id,
    a.admittime,
    a.dischtime
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON a.subject_id = p.subject_id
  WHERE 
    p.gender = 'M'
    AND (p.anchor_age + (EXTRACT(YEAR FROM a.admittime) - p.anchor_year)) BETWEEN 68 AND 78
    AND EXISTS (
      SELECT 1 
      FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
      INNER JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` dd 
        ON d.icd_code = dd.icd_code AND d.icd_version = dd.icd_version
      WHERE d.hadm_id = a.hadm_id
        AND (dd.icd_code LIKE 'E08%' OR dd.icd_code LIKE 'E09%' OR 
             dd.icd_code LIKE 'E10%' OR dd.icd_code LIKE 'E11%' OR 
             dd.icd_code LIKE 'E13%')
    )
    AND EXISTS (
      SELECT 1 
      FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
      INNER JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` dd 
        ON d.icd_code = dd.icd_code AND d.icd_version = dd.icd_version
      WHERE d.hadm_id = a.hadm_id
        AND (dd.icd_code LIKE 'I50.2%' OR dd.icd_code LIKE 'I50.3%')
    )
    AND a.dischtime IS NOT NULL
),
insulin_starts AS (
  SELECT 
    hadm_id,
    MIN(starttime) AS insulin_first_start
  FROM `physionet-data.mimiciv_3_1_hosp.prescriptions`
  WHERE 
    LOWER(drug) LIKE '%insulin%'
  GROUP BY hadm_id
),
oral_starts AS (
  SELECT 
    hadm_id,
    MIN(starttime) AS oral_first_start
  FROM `physionet-data.mimiciv_3_1_hosp.prescriptions`
  WHERE 
    (LOWER(drug) LIKE '%metformin%' OR
     LOWER(drug) LIKE '%glipizide%' OR
     LOWER(drug) LIKE '%glyburide%' OR
     LOWER(drug) LIKE '%glimepiride%' OR
     LOWER(drug) LIKE '%sitagliptin%' OR
     LOWER(drug) LIKE '%saxagliptin%' OR
     LOWER(drug) LIKE '%linagliptin%' OR
     LOWER(drug) LIKE '%alogliptin%' OR
     LOWER(drug) LIKE '%canagliflozin%' OR
     LOWER(drug) LIKE '%dapagliflozin%' OR
     LOWER(drug) LIKE '%empagliflozin%' OR
     LOWER(drug) LIKE '%ertugliflozin%' OR
     LOWER(drug) LIKE '%pioglitazone%' OR
     LOWER(drug) LIKE '%rosiglitazone%' OR
     LOWER(drug) LIKE '%repaglinide%' OR
     LOWER(drug) LIKE '%nateglinide%' OR
     LOWER(drug) LIKE '%acarbose%' OR
     LOWER(drug) LIKE '%miglitol%' OR
     LOWER(drug) LIKE '%bromocriptine%')
    AND LOWER(drug) NOT LIKE '%insulin%'
    AND LOWER(drug) NOT LIKE '%inject%'
    AND LOWER(drug) NOT LIKE '%subcut%'
    AND LOWER(drug) NOT LIKE '%iv%'
    AND LOWER(drug) NOT LIKE '%sc%'
  GROUP BY hadm_id
),
combined AS (
  SELECT 
    c.hadm_id,
    c.admittime,
    c.dischtime,
    i.insulin_first_start,
    o.oral_first_start,
    CASE WHEN i.insulin_first_start BETWEEN c.admittime AND c.admittime + INTERVAL '24' HOUR THEN 1 ELSE 0 END AS insulin_first_24h,
    CASE WHEN o.oral_first_start BETWEEN c.admittime AND c.admittime + INTERVAL '24' HOUR THEN 1 ELSE 0 END AS oral_first_24h,
    CASE WHEN i.insulin_first_start BETWEEN c.dischtime - INTERVAL '24' HOUR AND c.dischtime THEN 1 ELSE 0 END AS insulin_last_24h,
    CASE WHEN o.oral_first_start BETWEEN c.dischtime - INTERVAL '24' HOUR AND c.dischtime THEN 1 ELSE 0 END AS oral_last_24h
  FROM cohort c
  LEFT JOIN insulin_starts i ON c.hadm_id = i.hadm_id
  LEFT JOIN oral_starts o ON c.hadm_id = o.hadm_id
)
SELECT 
  'insulin' AS drug_class,
  SUM(insulin_first_24h) * 100.0 / COUNT(*) AS rate_first_24h,
  SUM(insulin_last_24h) * 100.0 / COUNT(*) AS rate_last_24h,
  (SUM(insulin_first_24h) - SUM(insulin_last_24h)) * 100.0 / COUNT(*) AS diff
FROM combined
UNION ALL
SELECT 
  'oral' AS drug_class,
  SUM(oral_first_24h) * 100.0 / COUNT(*) AS rate_first_24h,
  SUM(oral_last_24h) * 100.0 / COUNT(*) AS rate_last_24h,
  (SUM(oral_first_24h) - SUM(oral_last_24h)) * 100.0 / COUNT(*) AS diff
FROM combined;