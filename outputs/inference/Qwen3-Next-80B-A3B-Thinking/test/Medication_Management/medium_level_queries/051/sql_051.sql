WITH cohort AS (
  SELECT 
    p.subject_id, 
    a.hadm_id, 
    a.admittime, 
    a.dischtime
  FROM `physionet-data.mimiciv_3_1_hosp.patients` p
  JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a 
    ON p.subject_id = a.subject_id
  WHERE 
    p.gender = 'F'
    AND p.anchor_age BETWEEN 86 AND 96
    AND EXISTS (
      SELECT 1
      FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
      JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` d_icd
        ON d.icd_code = d_icd.icd_code AND d.icd_version = d_icd.icd_version
      WHERE 
        d.subject_id = p.subject_id 
        AND d.hadm_id = a.hadm_id
        AND (LOWER(d_icd.long_title) LIKE '%diabetes%' OR LOWER(d_icd.long_title) LIKE '%diabetic%')
    )
    AND EXISTS (
      SELECT 1
      FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
      JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` d_icd
        ON d.icd_code = d_icd.icd_code AND d.icd_version = d_icd.icd_version
      WHERE 
        d.subject_id = p.subject_id 
        AND d.hadm_id = a.hadm_id
        AND (LOWER(d_icd.long_title) LIKE '%heart failure%' OR LOWER(d_icd.long_title) LIKE '%congestive heart failure%')
    )
),

prescriptions_early AS (
  SELECT 
    c.subject_id, 
    c.hadm_id,
    MAX(CASE WHEN LOWER(pr.drug) LIKE '%insulin%' THEN 1 ELSE 0 END) AS has_insulin_early,
    MAX(CASE WHEN LOWER(pr.drug) IN ('metformin', 'glipizide', 'glyburide', 'pioglitazone', 'rosiglitazone', 'sitagliptin', 'linagliptin', 'empagliflozin', 'canagliflozin', 'dapagliflozin', 'glimepiride', 'repaglinide', 'nateglinide', 'chlorpropamide', 'tolbutamide', 'acetohexamide', 'tolazamide') THEN 1 ELSE 0 END) AS has_oral_early
  FROM cohort c
  JOIN `physionet-data.mimiciv_3_1_hosp.prescriptions` pr
    ON c.hadm_id = pr.hadm_id
  WHERE 
    pr.starttime BETWEEN c.admittime AND c.admittime + INTERVAL '12' HOUR
  GROUP BY c.subject_id, c.hadm_id
),

prescriptions_late AS (
  SELECT 
    c.subject_id, 
    c.hadm_id,
    MAX(CASE WHEN LOWER(pr.drug) LIKE '%insulin%' THEN 1 ELSE 0 END) AS has_insulin_late,
    MAX(CASE WHEN LOWER(pr.drug) IN ('metformin', 'glipizide', 'glyburide', 'pioglitazone', 'rosiglitazone', 'sitagliptin', 'linagliptin', 'empagliflozin', 'canagliflozin', 'dapagliflozin', 'glimepiride', 'repaglinide', 'nateglinide', 'chlorpropamide', 'tolbutamide', 'acetohexamide', 'tolazamide') THEN 1 ELSE 0 END) AS has_oral_late
  FROM cohort c
  JOIN `physionet-data.mimiciv_3_1_hosp.prescriptions` pr
    ON c.hadm_id = pr.hadm_id
  WHERE 
    pr.starttime BETWEEN c.dischtime - INTERVAL '72' HOUR AND c.dischtime
  GROUP BY c.subject_id, c.hadm_id
)

SELECT
  ROUND(SUM(COALESCE(e.has_insulin_early, 0)) * 100.0 / COUNT(*), 2) AS early_insulin_rate,
  ROUND(SUM(COALESCE(e.has_oral_early, 0)) * 100.0 / COUNT(*), 2) AS early_oral_rate,
  ROUND(SUM(COALESCE(l.has_insulin_late, 0)) * 100.0 / COUNT(*), 2) AS late_insulin_rate,
  ROUND(SUM(COALESCE(l.has_oral_late, 0)) * 100.0 / COUNT(*), 2) AS late_oral_rate,
  ROUND(SUM(CASE WHEN COALESCE(e.has_insulin_early, 0) = 1 AND COALESCE(l.has_insulin_late, 0) = 1 THEN 1 ELSE 0 END) * 100.0 / COUNT(*), 2) AS insulin_to_insulin,
  ROUND(SUM(CASE WHEN COALESCE(e.has_insulin_early, 0) = 1 AND COALESCE(l.has_oral_late, 0) = 1 THEN 1 ELSE 0 END) * 100.0 / COUNT(*), 2) AS insulin_to_oral,
  ROUND(SUM(CASE WHEN COALESCE(e.has_oral_early, 0) = 1 AND COALESCE(l.has_insulin_late, 0) = 1 THEN 1 ELSE 0 END) * 100.0 / COUNT(*), 2) AS oral_to_insulin,
  ROUND(SUM(CASE WHEN COALESCE(e.has_oral_early, 0) = 1 AND COALESCE(l.has_oral_late, 0) = 1 THEN 1 ELSE 0 END) * 100.0 / COUNT(*), 2) AS oral_to_oral
FROM cohort c
LEFT JOIN prescriptions_early e 
  ON c.subject_id = e.subject_id AND c.hadm_id = e.hadm_id
LEFT JOIN prescriptions_late l 
  ON c.subject_id = l.subject_id AND c.hadm_id = l.hadm_id;