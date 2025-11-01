WITH cohort AS (
  -- Patients aged 71-81 with diabetes and acute heart failure
  SELECT DISTINCT p.subject_id, a.hadm_id, a.admittime, a.dischtime
  FROM `physionet-data.mimiciv_3_1_hosp.patients` p
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a
    ON p.subject_id = a.subject_id
  WHERE p.anchor_age BETWEEN 71 AND 81
    AND EXISTS (
      -- Diabetes diagnosis
      SELECT 1
      FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
      WHERE d.subject_id = p.subject_id AND d.hadm_id = a.hadm_id
        AND (
          (d.icd_version = 10 AND d.icd_code LIKE 'E1%') OR
          (d.icd_version = 9 AND d.icd_code LIKE '250%')
        )
    )
    AND EXISTS (
      -- Acute heart failure diagnosis
      SELECT 1
      FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
      WHERE d.subject_id = p.subject_id AND d.hadm_id = a.hadm_id
        AND (
          (d.icd_version = 10 AND d.icd_code LIKE 'I50.2%') OR
          (d.icd_version = 9 AND d.icd_code IN ('428.0', '428.20', '428.21', '428.22', '428.23', '428.30', '428.31', '428.32', '428.33', '428.40', '428.41', '428.42', '428.43'))
        )
    )
),
drug_classes AS (
  -- Map drug names to classes
  SELECT
    subject_id,
    hadm_id,
    starttime,
    CASE
      WHEN LOWER(drug) LIKE '%metformin%' THEN 'metformin'
      WHEN LOWER(drug) LIKE '%glipizide%' OR LOWER(drug) LIKE '%glyburide%' OR LOWER(drug) LIKE '%glimepiride%' THEN 'sulfonylureas'
      WHEN LOWER(drug) LIKE '%sitagliptin%' OR LOWER(drug) LIKE '%saxagliptin%' OR LOWER(drug) LIKE '%linagliptin%' OR LOWER(drug) LIKE '%alogliptin%' THEN 'dpp4'
      WHEN LOWER(drug) LIKE '%canagliflozin%' OR LOWER(drug) LIKE '%dapagliflozin%' OR LOWER(drug) LIKE '%empagliflozin%' THEN 'sglt2'
      WHEN LOWER(drug) LIKE '%pioglitazone%' OR LOWER(drug) LIKE '%rosiglitazone%' THEN 'thiazolidinediones'
    END AS drug_class
  FROM `physionet-data.mimiciv_3_1_hosp.prescriptions`
  WHERE 
    LOWER(drug) LIKE '%metformin%' OR
    LOWER(drug) LIKE '%glipizide%' OR LOWER(drug) LIKE '%glyburide%' OR LOWER(drug) LIKE '%glimepiride%' OR
    LOWER(drug) LIKE '%sitagliptin%' OR LOWER(drug) LIKE '%saxagliptin%' OR LOWER(drug) LIKE '%linagliptin%' OR LOWER(drug) LIKE '%alogliptin%' OR
    LOWER(drug) LIKE '%canagliflozin%' OR LOWER(drug) LIKE '%dapagliflozin%' OR LOWER(drug) LIKE '%empagliflozin%' OR
    LOWER(drug) LIKE '%pioglitazone%' OR LOWER(drug) LIKE '%rosiglitazone%'
),
first_initiation AS (
  -- For each patient and drug class, get the first initiation time during the hospitalization
  SELECT
    c.subject_id,
    c.hadm_id,
    dc.drug_class,
    MIN(dc.starttime) AS first_starttime
  FROM cohort c
  INNER JOIN drug_classes dc
    ON c.subject_id = dc.subject_id AND c.hadm_id = dc.hadm_id
  GROUP BY c.subject_id, c.hadm_id, dc.drug_class
),
time_windows AS (
  -- For each patient, define the time windows
  SELECT
    subject_id,
    hadm_id,
    admittime,
    dischtime,
    DATETIME_ADD(admittime, INTERVAL 72 HOUR) AS first72h_end,
    DATETIME_SUB(dischtime, INTERVAL 48 HOUR) AS last48h_start
  FROM cohort
),
initiation_flags AS (
  -- Check if first initiation is in first72h or last48h
  SELECT
    fi.subject_id,
    fi.hadm_id,
    fi.drug_class,
    CASE WHEN fi.first_starttime BETWEEN tw.admittime AND tw.first72h_end THEN 1 ELSE 0 END AS in_first72h,
    CASE WHEN fi.first_starttime BETWEEN tw.last48h_start AND tw.dischtime THEN 1 ELSE 0 END AS in_last48h
  FROM first_initiation fi
  INNER JOIN time_windows tw
    ON fi.subject_id = tw.subject_id AND fi.hadm_id = tw.hadm_id
),
cohort_size AS (
  SELECT COUNT(DISTINCT subject_id) AS total_patients
  FROM cohort
),
aggregated AS (
  -- Count initiations per drug class and window
  SELECT
    drug_class,
    SUM(in_first72h) AS count_first72h,
    SUM(in_last48h) AS count_last48h
  FROM initiation_flags
  GROUP BY drug_class
)
-- Calculate percentages
SELECT
  drug_class,
  count_first72h,
  ROUND(100.0 * count_first72h / cs.total_patients, 2) AS pct_first72h,
  count_last48h,
  ROUND(100.0 * count_last48h / cs.total_patients, 2) AS pct_last48h
FROM aggregated, cohort_size cs
ORDER BY drug_class;