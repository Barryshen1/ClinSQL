WITH classes AS (
  SELECT 'insulin' AS drug_class UNION ALL
  SELECT 'met' UNION ALL
  SELECT 'SU' UNION ALL
  SELECT 'DPP-4' UNION ALL
  SELECT 'SGLT2' UNION ALL
  SELECT 'GLP-1' UNION ALL
  SELECT 'TZD'
),
cohort AS (
  SELECT 
    a.subject_id, 
    a.hadm_id, 
    a.admittime, 
    a.dischtime
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` p 
    ON a.subject_id = p.subject_id
  WHERE p.gender = 'F'
    AND p.anchor_age BETWEEN 67 AND 77
    AND EXISTS (
      SELECT 1 
      FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d 
      WHERE d.hadm_id = a.hadm_id 
        AND d.icd_code LIKE 'E11%'
    )
    AND EXISTS (
      SELECT 1 
      FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d 
      WHERE d.hadm_id = a.hadm_id 
        AND d.icd_code LIKE 'I50%'
    )
),
prescriptions_with_class AS (
  SELECT 
    c.subject_id,
    c.hadm_id,
    c.admittime,
    c.dischtime,
    p.starttime,
    CASE 
      WHEN p.drug LIKE '%insulin%' THEN 'insulin'
      WHEN p.drug LIKE '%metformin%' OR p.drug LIKE '%glucophage%' THEN 'met'
      WHEN p.drug LIKE '%glipizide%' OR p.drug LIKE '%glyburide%' OR p.drug LIKE '%gliclazide%' OR p.drug LIKE '%glucotrol%' OR p.drug LIKE '%micronase%' THEN 'SU'
      WHEN p.drug LIKE '%sitagliptin%' OR p.drug LIKE '%linagliptin%' OR p.drug LIKE '%saxagliptin%' THEN 'DPP-4'
      WHEN p.drug LIKE '%empagliflozin%' OR p.drug LIKE '%canagliflozin%' OR p.drug LIKE '%dapagliflozin%' THEN 'SGLT2'
      WHEN p.drug LIKE '%liraglutide%' OR p.drug LIKE '%semaglutide%' OR p.drug LIKE '%exenatide%' THEN 'GLP-1'
      WHEN p.drug LIKE '%pioglitazone%' OR p.drug LIKE '%rosiglitazone%' THEN 'TZD'
      ELSE NULL
    END AS drug_class
  FROM cohort c
  JOIN `physionet-data.mimiciv_3_1_hosp.prescriptions` p 
    ON c.hadm_id = p.hadm_id
  WHERE p.drug IS NOT NULL
    AND p.starttime IS NOT NULL
),
time_windows AS (
  SELECT 
    subject_id,
    drug_class,
    MAX(CASE WHEN starttime BETWEEN admittime AND admittime + INTERVAL '12' HOUR THEN 1 ELSE 0 END) AS first_12h_initiated,
    MAX(CASE WHEN starttime BETWEEN dischtime - INTERVAL '48' HOUR AND dischtime THEN 1 ELSE 0 END) AS last_48h_initiated
  FROM prescriptions_with_class
  WHERE drug_class IS NOT NULL
  GROUP BY subject_id, drug_class
),
total_patients AS (
  SELECT COUNT(DISTINCT subject_id) AS total FROM cohort
)
SELECT 
  c.drug_class,
  ROUND(COALESCE(SUM(t.first_12h_initiated), 0) * 100.0 / (SELECT total FROM total_patients), 2) AS first_12h_pct,
  ROUND(COALESCE(SUM(t.last_48h_initiated), 0) * 100.0 / (SELECT total FROM total_patients), 2) AS last_48h_pct,
  ROUND((COALESCE(SUM(t.last_48h_initiated), 0) - COALESCE(SUM(t.first_12h_initiated), 0)) * 100.0 / (SELECT total FROM total_patients), 2) AS net_change
FROM classes c
LEFT JOIN time_windows t ON c.drug_class = t.drug_class
GROUP BY c.drug_class;