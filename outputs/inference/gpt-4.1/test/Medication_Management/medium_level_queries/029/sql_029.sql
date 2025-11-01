WITH cohort AS (
  -- Select admissions for females aged 69-79 with T2DM and heart failure
  SELECT
    a.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime
  FROM
    `physionet-data.mimiciv_3_1_hosp.admissions` a
    JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
      ON a.subject_id = p.subject_id
  WHERE
    p.gender = 'F'
    AND p.anchor_age BETWEEN 69 AND 79
    AND EXISTS (
      SELECT 1
      FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
      WHERE d.hadm_id = a.hadm_id
        AND (
          -- T2DM ICD-10 E11.*, ICD-9 250.x0, 250.x2
          (d.icd_version = 10 AND LEFT(d.icd_code, 3) = 'E11')
          OR (d.icd_version = 9 AND LEFT(d.icd_code, 3) = '250' AND RIGHT(d.icd_code, 2) IN ('00','02','10','12','20','22','30','32','40','42','50','52','60','62','70','72','80','82','90','92'))
        )
    )
    AND EXISTS (
      SELECT 1
      FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
      WHERE d.hadm_id = a.hadm_id
        AND (
          -- Heart Failure ICD-10 I50.*, ICD-9 428.*
          (d.icd_version = 10 AND LEFT(d.icd_code, 3) = 'I50')
          OR (d.icd_version = 9 AND LEFT(d.icd_code, 3) = '428')
        )
    )
),
drug_classes AS (
  -- Map drug names to classes
  SELECT 'insulin' AS drug_class, r.hadm_id, r.subject_id, r.starttime
  FROM `physionet-data.mimiciv_3_1_hosp.prescriptions` r
  WHERE LOWER(r.drug) LIKE '%insulin%'
  UNION ALL
  SELECT 'metformin', r.hadm_id, r.subject_id, r.starttime
  FROM `physionet-data.mimiciv_3_1_hosp.prescriptions` r
  WHERE LOWER(r.drug) LIKE '%metformin%'
  UNION ALL
  SELECT 'sulfonylurea', r.hadm_id, r.subject_id, r.starttime
  FROM `physionet-data.mimiciv_3_1_hosp.prescriptions` r
  WHERE LOWER(r.drug) LIKE '%glipizide%' OR LOWER(r.drug) LIKE '%glyburide%' OR LOWER(r.drug) LIKE '%glimepiride%' OR LOWER(r.drug) LIKE '%tolbutamide%' OR LOWER(r.drug) LIKE '%chlorpropamide%' OR LOWER(r.drug) LIKE '%tolazamide%' OR LOWER(r.drug) LIKE '%acetohexamide%' OR LOWER(r.drug) LIKE '%gliclazide%'
  UNION ALL
  SELECT 'dpp4', r.hadm_id, r.subject_id, r.starttime
  FROM `physionet-data.mimiciv_3_1_hosp.prescriptions` r
  WHERE LOWER(r.drug) LIKE '%sitagliptin%' OR LOWER(r.drug) LIKE '%saxagliptin%' OR LOWER(r.drug) LIKE '%linagliptin%' OR LOWER(r.drug) LIKE '%alogliptin%'
  UNION ALL
  SELECT 'sglt2', r.hadm_id, r.subject_id, r.starttime
  FROM `physionet-data.mimiciv_3_1_hosp.prescriptions` r
  WHERE LOWER(r.drug) LIKE '%canagliflozin%' OR LOWER(r.drug) LIKE '%dapagliflozin%' OR LOWER(r.drug) LIKE '%empagliflozin%' OR LOWER(r.drug) LIKE '%ertugliflozin%'
  UNION ALL
  SELECT 'glp1', r.hadm_id, r.subject_id, r.starttime
  FROM `physionet-data.mimiciv_3_1_hosp.prescriptions` r
  WHERE LOWER(r.drug) LIKE '%exenatide%' OR LOWER(r.drug) LIKE '%liraglutide%' OR LOWER(r.drug) LIKE '%dulaglutide%' OR LOWER(r.drug) LIKE '%semaglutide%' OR LOWER(r.drug) LIKE '%lixisenatide%'
  UNION ALL
  SELECT 'tzd', r.hadm_id, r.subject_id, r.starttime
  FROM `physionet-data.mimiciv_3_1_hosp.prescriptions` r
  WHERE LOWER(r.drug) LIKE '%pioglitazone%' OR LOWER(r.drug) LIKE '%rosiglitazone%'
),
exposure AS (
  -- For each cohort admission, flag exposure to each drug class in first/last 72h
  SELECT
    c.subject_id,
    c.hadm_id,
    dc.drug_class,
    CASE
      WHEN dc.starttime BETWEEN c.admittime AND DATETIME_ADD(c.admittime, INTERVAL 72 HOUR) THEN 'first_72h'
      WHEN dc.starttime BETWEEN DATETIME_SUB(c.dischtime, INTERVAL 72 HOUR) AND c.dischtime THEN 'last_72h'
      ELSE NULL
    END AS time_window
  FROM cohort c
  JOIN drug_classes dc
    ON c.hadm_id = dc.hadm_id
  WHERE
    -- Only keep exposures in first or last 72h
    (
      dc.starttime BETWEEN c.admittime AND DATETIME_ADD(c.admittime, INTERVAL 72 HOUR)
      OR dc.starttime BETWEEN DATETIME_SUB(c.dischtime, INTERVAL 72 HOUR) AND c.dischtime
    )
),
summary AS (
  -- Aggregate: for each drug class and time window, count unique admissions exposed
  SELECT
    drug_class,
    time_window,
    COUNT(DISTINCT hadm_id) AS n_exposed
  FROM exposure
  WHERE time_window IS NOT NULL
  GROUP BY drug_class, time_window
),
cohort_size AS (
  SELECT COUNT(DISTINCT hadm_id) AS n_cohort FROM cohort
)
SELECT
  s.drug_class,
  s.time_window,
  ROUND(100.0 * s.n_exposed / c.n_cohort, 1) AS percent_exposed
FROM summary s
CROSS JOIN cohort_size c
ORDER BY s.drug_class, s.time_window;