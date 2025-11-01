WITH cohort AS (
  SELECT 
    a.hadm_id,
    a.admittime,
    a.dischtime
  FROM 
    `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN 
    `physionet-data.mimiciv_3_1_hosp.patients` p 
    ON a.subject_id = p.subject_id
  WHERE 
    p.anchor_age BETWEEN 71 AND 81
    AND p.gender = 'M'
    AND EXISTS (
      SELECT 1
      FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
      JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` di 
        ON d.icd_code = di.icd_code AND d.icd_version = di.icd_version
      WHERE d.hadm_id = a.hadm_id
        AND (
          (d.icd_version = 9 AND d.icd_code LIKE '250%')
          OR (d.icd_version = 10 AND (d.icd_code LIKE 'E08%' OR d.icd_code LIKE 'E09%' OR d.icd_code LIKE 'E10%' OR d.icd_code LIKE 'E11%' OR d.icd_code LIKE 'E13%'))
        )
    )
    AND EXISTS (
      SELECT 1
      FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
      JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` di 
        ON d.icd_code = di.icd_code AND d.icd_version = di.icd_version
      WHERE d.hadm_id = a.hadm_id
        AND (
          (d.icd_version = 9 AND d.icd_code LIKE '428%')
          OR (d.icd_version = 10 AND d.icd_code LIKE 'I50%')
        )
    )
)

SELECT 
  'metformin' AS medication_class,
  SUM(CASE WHEN EXISTS (
    SELECT 1 
    FROM `physionet-data.mimiciv_3_1_hosp.prescriptions` p 
    WHERE p.hadm_id = c.hadm_id 
      AND LOWER(p.drug) LIKE '%metformin%' 
      AND p.starttime BETWEEN c.admittime AND DATETIME_ADD(c.admittime, INTERVAL 72 HOUR)
  ) THEN 1 ELSE 0 END) * 100.0 / COUNT(*) AS first_72h_rate,
  SUM(CASE WHEN EXISTS (
    SELECT 1 
    FROM `physionet-data.mimiciv_3_1_hosp.prescriptions` p 
    WHERE p.hadm_id = c.hadm_id 
      AND LOWER(p.drug) LIKE '%metformin%' 
      AND p.starttime BETWEEN DATETIME_SUB(c.dischtime, INTERVAL 48 HOUR) AND c.dischtime
  ) THEN 1 ELSE 0 END) * 100.0 / COUNT(*) AS last_48h_rate
FROM cohort c

UNION ALL

SELECT 
  'sulfonylureas' AS medication_class,
  SUM(CASE WHEN EXISTS (
    SELECT 1 
    FROM `physionet-data.mimiciv_3_1_hosp.prescriptions` p 
    WHERE p.hadm_id = c.hadm_id 
      AND (
        LOWER(p.drug) LIKE '%glipizide%' 
        OR LOWER(p.drug) LIKE '%glyburide%' 
        OR LOWER(p.drug) LIKE '%glimepiride%' 
        OR LOWER(p.drug) LIKE '%tolbutamide%' 
        OR LOWER(p.drug) LIKE '%chlorpropamide%' 
        OR LOWER(p.drug) LIKE '%glibenclamide%'
      )
      AND p.starttime BETWEEN c.admittime AND DATETIME_ADD(c.admittime, INTERVAL 72 HOUR)
  ) THEN 1 ELSE 0 END) * 100.0 / COUNT(*) AS first_72h_rate,
  SUM(CASE WHEN EXISTS (
    SELECT 1 
    FROM `physionet-data.mimiciv_3_1_hosp.prescriptions` p 
    WHERE p.hadm_id = c.hadm_id 
      AND (
        LOWER(p.drug) LIKE '%glipizide%' 
        OR LOWER(p.drug) LIKE '%glyburide%' 
        OR LOWER(p.drug) LIKE '%glimepiride%' 
        OR LOWER(p.drug) LIKE '%tolbutamide%' 
        OR LOWER(p.drug) LIKE '%chlorpropamide%' 
        OR LOWER(p.drug) LIKE '%glibenclamide%'
      )
      AND p.starttime BETWEEN DATETIME_SUB(c.dischtime, INTERVAL 48 HOUR) AND c.dischtime
  ) THEN 1 ELSE 0 END) * 100.0 / COUNT(*) AS last_48h_rate
FROM cohort c

UNION ALL

SELECT 
  'dpp4_inhibitors' AS medication_class,
  SUM(CASE WHEN EXISTS (
    SELECT 1 
    FROM `physionet-data.mimiciv_3_1_hosp.prescriptions` p 
    WHERE p.hadm_id = c.hadm_id 
      AND (
        LOWER(p.drug) LIKE '%sitagliptin%' 
        OR LOWER(p.drug) LIKE '%saxagliptin%' 
        OR LOWER(p.drug) LIKE '%linagliptin%' 
        OR LOWER(p.drug) LIKE '%alogliptin%' 
        OR LOWER(p.drug) LIKE '%vildagliptin%'
      )
      AND p.starttime BETWEEN c.admittime AND DATETIME_ADD(c.admittime, INTERVAL 72 HOUR)
  ) THEN 1 ELSE 0 END) * 100.0 / COUNT(*) AS first_72h_rate,
  SUM(CASE WHEN EXISTS (
    SELECT 1 
    FROM `physionet-data.mimiciv_3_1_hosp.prescriptions` p 
    WHERE p.hadm_id = c.hadm_id 
      AND (
        LOWER(p.drug) LIKE '%sitagliptin%' 
        OR LOWER(p.drug) LIKE '%saxagliptin%' 
        OR LOWER(p.drug) LIKE '%linagliptin%' 
        OR LOWER(p.drug) LIKE '%alogliptin%' 
        OR LOWER(p.drug) LIKE '%vildagliptin%'
      )
      AND p.starttime BETWEEN DATETIME_SUB(c.dischtime, INTERVAL 48 HOUR) AND c.dischtime
  ) THEN 1 ELSE 0 END) * 100.0 / COUNT(*) AS last_48h_rate
FROM cohort c

UNION ALL

SELECT 
  'sglt2_inhibitors' AS medication_class,
  SUM(CASE WHEN EXISTS (
    SELECT 1 
    FROM `physionet-data.mimiciv_3_1_hosp.prescriptions` p 
    WHERE p.hadm_id = c.hadm_id 
      AND (
        LOWER(p.drug) LIKE '%canagliflozin%' 
        OR LOWER(p.drug) LIKE '%dapagliflozin%' 
        OR LOWER(p.drug) LIKE '%empagliflozin%' 
        OR LOWER(p.drug) LIKE '%ertugliflozin%'
      )
      AND p.starttime BETWEEN c.admittime AND DATETIME_ADD(c.admittime, INTERVAL 72 HOUR)
  ) THEN 1 ELSE 0 END) * 100.0 / COUNT(*) AS first_72h_rate,
  SUM(CASE WHEN EXISTS (
    SELECT 1 
    FROM `physionet-data.mimiciv_3_1_hosp.prescriptions` p 
    WHERE p.hadm_id = c.hadm_id 
      AND (
        LOWER(p.drug) LIKE '%canagliflozin%' 
        OR LOWER(p.drug) LIKE '%dapagliflozin%' 
        OR LOWER(p.drug) LIKE '%empagliflozin%' 
        OR LOWER(p.drug) LIKE '%ertugliflozin%'
      )
      AND p.starttime BETWEEN DATETIME_SUB(c.dischtime, INTERVAL 48 HOUR) AND c.dischtime
  ) THEN 1 ELSE 0 END) * 100.0 / COUNT(*) AS last_48h_rate
FROM cohort c

UNION ALL

SELECT 
  'thiazolidinediones' AS medication_class,
  SUM(CASE WHEN EXISTS (
    SELECT 1 
    FROM `physionet-data.mimiciv_3_1_hosp.prescriptions` p 
    WHERE p.hadm_id = c.hadm_id 
      AND (
        LOWER(p.drug) LIKE '%pioglitazone%' 
        OR LOWER(p.drug) LIKE '%rosiglitazone%'
      )
      AND p.starttime BETWEEN c.admittime AND DATETIME_ADD(c.admittime, INTERVAL 72 HOUR)
  ) THEN 1 ELSE 0 END) * 100.0 / COUNT(*) AS first_72h_rate,
  SUM(CASE WHEN EXISTS (
    SELECT 1 
    FROM `physionet-data.mimiciv_3_1_hosp.prescriptions` p 
    WHERE p.hadm_id = c.hadm_id 
      AND (
        LOWER(p.drug) LIKE '%pioglitazone%' 
        OR LOWER(p.drug) LIKE '%rosiglitazone%'
      )
      AND p.starttime BETWEEN DATETIME_SUB(c.dischtime, INTERVAL 48 HOUR) AND c.dischtime
  ) THEN 1 ELSE 0 END) * 100.0 / COUNT(*) AS last_48h_rate
FROM cohort c;