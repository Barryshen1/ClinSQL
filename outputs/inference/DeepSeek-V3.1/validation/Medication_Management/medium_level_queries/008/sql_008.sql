WITH cohort AS (
  SELECT 
    p.subject_id, 
    a.hadm_id, 
    a.admittime, 
    a.dischtime
  FROM `physionet-data.mimiciv_3_1_hosp.patients` p
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a
    ON p.subject_id = a.subject_id
  WHERE p.gender = 'F'
    AND p.anchor_age BETWEEN 44 AND 54
    AND EXISTS (
      SELECT 1
      FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` di
      WHERE di.subject_id = p.subject_id
        AND di.hadm_id = a.hadm_id
        AND di.icd_code LIKE 'E11%'
        AND di.icd_version = 10
    )
    AND EXISTS (
      SELECT 1
      FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` di
      WHERE di.subject_id = p.subject_id
        AND di.hadm_id = a.hadm_id
        AND di.icd_code LIKE 'I50%'
        AND di.icd_version = 10
    )
),

insulin AS (
  SELECT 
    subject_id,
    hadm_id,
    starttime,
    stoptime,
    'insulin' AS drug_class
  FROM `physionet-data.mimiciv_3_1_hosp.prescriptions`
  WHERE LOWER(drug) LIKE '%insulin%'
),

oral_agents AS (
  SELECT 
    subject_id,
    hadm_id,
    starttime,
    stoptime,
    'oral_agent' AS drug_class
  FROM `physionet-data.mimiciv_3_1_hosp.prescriptions`
  WHERE LOWER(drug) LIKE '%metformin%'
    OR LOWER(drug) LIKE '%glipizide%'
    OR LOWER(drug) LIKE '%glyburide%'
    OR LOWER(drug) LIKE '%glimepiride%'
    OR LOWER(drug) LIKE '%pioglitazone%'
    OR LOWER(drug) LIKE '%rosiglitazone%'
    OR LOWER(drug) LIKE '%sitagliptin%'
    OR LOWER(drug) LIKE '%saxagliptin%'
    OR LOWER(drug) LIKE '%linagliptin%'
    OR LOWER(drug) LIKE '%dapagliflozin%'
    OR LOWER(drug) LIKE '%empagliflozin%'
    OR LOWER(drug) LIKE '%canagliflozin%'
    OR LOWER(drug) LIKE '%repaglinide%'
    OR LOWER(drug) LIKE '%nateglinide%'
),

all_drugs AS (
  SELECT * FROM insulin
  UNION ALL
  SELECT * FROM oral_agents
),

drugs_with_windows AS (
  SELECT 
    c.subject_id,
    c.hadm_id,
    c.admittime,
    c.dischtime,
    d.drug_class,
    d.starttime,
    d.stoptime,
    -- First 24h window
    CASE WHEN d.starttime <= DATETIME_ADD(c.admittime, INTERVAL 24 HOUR) 
          AND (d.stoptime IS NULL OR d.stoptime >= c.admittime) THEN 1
         ELSE 0 END AS in_first_24h,
    -- Last 48h window
    CASE WHEN d.starttime <= c.dischtime 
          AND (d.stoptime IS NULL OR d.stoptime >= DATETIME_SUB(c.dischtime, INTERVAL 48 HOUR)) THEN 1
         ELSE 0 END AS in_last_48h,
    -- For last 48h: initiated, continued, discontinued
    CASE WHEN d.starttime >= DATETIME_SUB(c.dischtime, INTERVAL 48 HOUR) THEN 'initiated'
         WHEN d.starttime < DATETIME_SUB(c.dischtime, INTERVAL 48 HOUR) 
              AND (d.stoptime IS NULL OR d.stoptime >= c.dischtime) THEN 'continued'
         WHEN d.stoptime >= DATETIME_SUB(c.dischtime, INTERVAL 48 HOUR) 
              AND d.stoptime < c.dischtime THEN 'discontinued'
         ELSE 'other' END AS status_last_48h
  FROM cohort c
  INNER JOIN all_drugs d
    ON c.subject_id = d.subject_id AND c.hadm_id = d.hadm_id
),

agg_drugs AS (
  SELECT 
    subject_id,
    hadm_id,
    drug_class,
    MAX(in_first_24h) AS any_first_24h,
    MAX(in_last_48h) AS any_last_48h,
    -- For last 48h status, we take the first non-other status (assuming one drug class per patient)
    MAX(CASE WHEN status_last_48h = 'initiated' THEN 1 ELSE 0 END) AS initiated,
    MAX(CASE WHEN status_last_48h = 'continued' THEN 1 ELSE 0 END) AS continued,
    MAX(CASE WHEN status_last_48h = 'discontinued' THEN 1 ELSE 0 END) AS discontinued
  FROM drugs_with_windows
  GROUP BY subject_id, hadm_id, drug_class
)

SELECT 
  drug_class,
  -- Prevalence in first 24h
  COUNT(*) AS total_patients,
  ROUND(100 * SUM(any_first_24h) / COUNT(*), 2) AS prevalence_first_24h_percent,
  ROUND(100 * SUM(any_last_48h) / COUNT(*), 2) AS prevalence_last_48h_percent,
  -- Counts for last 48h
  SUM(initiated) AS initiated_count,
  SUM(continued) AS continued_count,
  SUM(discontinued) AS discontinued_count
FROM agg_drugs
GROUP BY drug_class;