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
    AND p.anchor_age BETWEEN 51 AND 61
    AND EXISTS (
      SELECT 1
      FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
      JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` di 
        ON d.icd_code = di.icd_code AND d.icd_version = di.icd_version
      WHERE 
        d.subject_id = p.subject_id 
        AND d.hadm_id = a.hadm_id
        AND LOWER(di.long_title) LIKE '%diabetes%'
    )
    AND EXISTS (
      SELECT 1
      FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
      JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` di 
        ON d.icd_code = di.icd_code AND d.icd_version = di.icd_version
      WHERE 
        d.subject_id = p.subject_id 
        AND d.hadm_id = a.hadm_id
        AND LOWER(di.long_title) LIKE '%heart failure%'
    )
),
first_48h AS (
  SELECT 
    c.subject_id, 
    c.hadm_id,
    MAX(CASE WHEN LOWER(pr.drug) LIKE '%insulin%' THEN 1 ELSE 0 END) AS insulin_first,
    MAX(CASE WHEN pr.route = 'Oral' AND (
      LOWER(pr.drug) LIKE '%metformin%' OR 
      LOWER(pr.drug) LIKE '%glipizide%' OR 
      LOWER(pr.drug) LIKE '%sitagliptin%' OR 
      LOWER(pr.drug) LIKE '%pioglitazone%' OR 
      LOWER(pr.drug) LIKE '%glyburide%' OR 
      LOWER(pr.drug) LIKE '%glimepiride%' OR 
      LOWER(pr.drug) LIKE '%repaglinide%' OR 
      LOWER(pr.drug) LIKE '%nateglinide%' OR 
      LOWER(pr.drug) LIKE '%vildagliptin%' OR 
      LOWER(pr.drug) LIKE '%alogliptin%' OR 
      LOWER(pr.drug) LIKE '%linagliptin%' OR 
      LOWER(pr.drug) LIKE '%dapagliflozin%' OR 
      LOWER(pr.drug) LIKE '%canagliflozin%' OR 
      LOWER(pr.drug) LIKE '%empagliflozin%'
    ) THEN 1 ELSE 0 END) AS oral_first
  FROM cohort c
  LEFT JOIN `physionet-data.mimiciv_3_1_hosp.prescriptions` pr
    ON c.subject_id = pr.subject_id 
    AND c.hadm_id = pr.hadm_id
    AND pr.starttime <= c.admittime + INTERVAL '48' HOUR
    AND pr.stoptime >= c.admittime
  GROUP BY c.subject_id, c.hadm_id
),
final_24h AS (
  SELECT 
    c.subject_id, 
    c.hadm_id,
    MAX(CASE WHEN LOWER(pr.drug) LIKE '%insulin%' THEN 1 ELSE 0 END) AS insulin_final,
    MAX(CASE WHEN pr.route = 'Oral' AND (
      LOWER(pr.drug) LIKE '%metformin%' OR 
      LOWER(pr.drug) LIKE '%glipizide%' OR 
      LOWER(pr.drug) LIKE '%sitagliptin%' OR 
      LOWER(pr.drug) LIKE '%pioglitazone%' OR 
      LOWER(pr.drug) LIKE '%glyburide%' OR 
      LOWER(pr.drug) LIKE '%glimepiride%' OR 
      LOWER(pr.drug) LIKE '%repaglinide%' OR 
      LOWER(pr.drug) LIKE '%nateglinide%' OR 
      LOWER(pr.drug) LIKE '%vildagliptin%' OR 
      LOWER(pr.drug) LIKE '%alogliptin%' OR 
      LOWER(pr.drug) LIKE '%linagliptin%' OR 
      LOWER(pr.drug) LIKE '%dapagliflozin%' OR 
      LOWER(pr.drug) LIKE '%canagliflozin%' OR 
      LOWER(pr.drug) LIKE '%empagliflozin%'
    ) THEN 1 ELSE 0 END) AS oral_final
  FROM cohort c
  LEFT JOIN `physionet-data.mimiciv_3_1_hosp.prescriptions` pr
    ON c.subject_id = pr.subject_id 
    AND c.hadm_id = pr.hadm_id
    AND pr.starttime <= c.dischtime
    AND pr.stoptime >= c.dischtime - INTERVAL '24' HOUR
  GROUP BY c.subject_id, c.hadm_id
),
combined AS (
  SELECT 
    f.subject_id,
    f.insulin_first,
    f.oral_first,
    fi.insulin_final,
    fi.oral_final
  FROM first_48h f
  JOIN final_24h fi 
    ON f.subject_id = fi.subject_id AND f.hadm_id = fi.hadm_id
)
SELECT 
  'First 48h' AS period,
  SUM(insulin_first) * 100.0 / COUNT(*) AS insulin_percent,
  SUM(oral_first) * 100.0 / COUNT(*) AS oral_percent
FROM combined
UNION ALL
SELECT 
  'Final 24h' AS period,
  SUM(insulin_final) * 100.0 / COUNT(*) AS insulin_percent,
  SUM(oral_final) * 100.0 / COUNT(*) AS oral_percent
FROM combined
UNION ALL
SELECT 
  'Insulin Continued' AS metric,
  SUM(CASE WHEN insulin_first = 1 AND insulin_final = 1 THEN 1 ELSE 0 END) AS count,
  NULL
FROM combined
UNION ALL
SELECT 
  'Insulin Initiated' AS metric,
  SUM(CASE WHEN insulin_first = 0 AND insulin_final = 1 THEN 1 ELSE 0 END) AS count,
  NULL
FROM combined
UNION ALL
SELECT 
  'Insulin Discontinued' AS metric,
  SUM(CASE WHEN insulin_first = 1 AND insulin_final = 0 THEN 1 ELSE 0 END) AS count,
  NULL
FROM combined
UNION ALL
SELECT 
  'Oral Continued' AS metric,
  SUM(CASE WHEN oral_first = 1 AND oral_final = 1 THEN 1 ELSE 0 END) AS count,
  NULL
FROM combined
UNION ALL
SELECT 
  'Oral Initiated' AS metric,
  SUM(CASE WHEN oral_first = 0 AND oral_final = 1 THEN 1 ELSE 0 END) AS count,
  NULL
FROM combined
UNION ALL
SELECT 
  'Oral Discontinued' AS metric,
  SUM(CASE WHEN oral_first = 1 AND oral_final = 0 THEN 1 ELSE 0 END) AS count,
  NULL
FROM combined;