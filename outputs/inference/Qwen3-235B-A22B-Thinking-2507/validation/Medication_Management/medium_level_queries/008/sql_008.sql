WITH cohort_admissions AS (
  SELECT 
    a.hadm_id,
    a.admittime,
    a.dischtime,
    p.anchor_age + EXTRACT(YEAR FROM a.admittime) - p.anchor_year AS age_at_adm
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON a.subject_id = p.subject_id
  WHERE p.gender = 'F'
    AND (p.anchor_age + EXTRACT(YEAR FROM a.admittime) - p.anchor_year) BETWEEN 44 AND 54
    AND EXISTS (
      SELECT 1 
      FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d1
      WHERE d1.hadm_id = a.hadm_id
        AND d1.icd_version = 10
        AND d1.icd_code LIKE 'E11%'
    )
    AND EXISTS (
      SELECT 1 
      FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d2
      WHERE d2.hadm_id = a.hadm_id
        AND d2.icd_version = 10
        AND d2.icd_code LIKE 'I50%'
    )
),

prescriptions_flagged AS (
  SELECT 
    p.*,
    CASE WHEN LOWER(p.drug) LIKE '%insulin%' THEN 1 ELSE 0 END AS is_insulin,
    CASE 
      WHEN LOWER(p.drug) LIKE '%metformin%' THEN 1
      WHEN LOWER(p.drug) LIKE '%glipizide%' THEN 1
      WHEN LOWER(p.drug) LIKE '%glyburide%' THEN 1
      WHEN LOWER(p.drug) LIKE '%glimepiride%' THEN 1
      WHEN LOWER(p.drug) LIKE '%sitagliptin%' THEN 1
      WHEN LOWER(p.drug) LIKE '%saxagliptin%' THEN 1
      WHEN LOWER(p.drug) LIKE '%linagliptin%' THEN 1
      WHEN LOWER(p.drug) LIKE '%alogliptin%' THEN 1
      WHEN LOWER(p.drug) LIKE '%canagliflozin%' THEN 1
      WHEN LOWER(p.drug) LIKE '%dapagliflozin%' THEN 1
      WHEN LOWER(p.drug) LIKE '%empagliflozin%' THEN 1
      WHEN LOWER(p.drug) LIKE '%ertugliflozin%' THEN 1
      WHEN LOWER(p.drug) LIKE '%pioglitazone%' THEN 1
      WHEN LOWER(p.drug) LIKE '%rosiglitazone%' THEN 1
      WHEN LOWER(p.drug) LIKE '%nateglinide%' THEN 1
      WHEN LOWER(p.drug) LIKE '%repaglinide%' THEN 1
      ELSE 0
    END AS is_oral_agent
  FROM `physionet-data.mimiciv_3_1_hosp.prescriptions` p
),

medication_usage AS (
  SELECT 
    ca.hadm_id,
    MAX(CASE WHEN pf.is_insulin = 1 AND 
               pf.starttime <= ca.admittime + INTERVAL '24' HOUR AND
               (pf.stoptime >= ca.admittime OR pf.stoptime IS NULL)
            THEN 1 ELSE 0 END) AS window1_insulin,
    MAX(CASE WHEN pf.is_insulin = 1 AND 
               pf.starttime <= ca.dischtime AND
               (pf.stoptime >= GREATEST(ca.admittime, ca.dischtime - INTERVAL '48' HOUR) OR pf.stoptime IS NULL)
            THEN 1 ELSE 0 END) AS window2_insulin,
    MAX(CASE WHEN pf.is_oral_agent = 1 AND 
               pf.starttime <= ca.admittime + INTERVAL '24' HOUR AND
               (pf.stoptime >= ca.admittime OR pf.stoptime IS NULL)
            THEN 1 ELSE 0 END) AS window1_oral,
    MAX(CASE WHEN pf.is_oral_agent = 1 AND 
               pf.starttime <= ca.dischtime AND
               (pf.stoptime >= GREATEST(ca.admittime, ca.dischtime - INTERVAL '48' HOUR) OR pf.stoptime IS NULL)
            THEN 1 ELSE 0 END) AS window2_oral
  FROM cohort_admissions ca
  LEFT JOIN prescriptions_flagged pf
    ON ca.hadm_id = pf.hadm_id
  GROUP BY ca.hadm_id
),

summary_stats AS (
  SELECT
    'insulin' AS drug_class,
    AVG(window1_insulin) * 100 AS window1_prevalence,
    AVG(window2_insulin) * 100 AS window2_prevalence,
    SUM(CASE WHEN window1_insulin = 1 AND window2_insulin = 1 THEN 1 ELSE 0 END) AS continued_count,
    SUM(CASE WHEN window1_insulin = 0 AND window2_insulin = 1 THEN 1 ELSE 0 END) AS initiated_count,
    SUM(CASE WHEN window1_insulin = 1 AND window2_insulin = 0 THEN 1 ELSE 0 END) AS discontinued_count
  FROM medication_usage
  
  UNION ALL
  
  SELECT
    'oral_agents' AS drug_class,
    AVG(window1_oral) * 100 AS window1_prevalence,
    AVG(window2_oral) * 100 AS window2_prevalence,
    SUM(CASE WHEN window1_oral = 1 AND window2_oral = 1 THEN 1 ELSE 0 END) AS continued_count,
    SUM(CASE WHEN window1_oral = 0 AND window2_oral = 1 THEN 1 ELSE 0 END) AS initiated_count,
    SUM(CASE WHEN window1_oral = 1 AND window2_oral = 0 THEN 1 ELSE 0 END) AS discontinued_count
  FROM medication_usage
)

SELECT * FROM summary_stats;