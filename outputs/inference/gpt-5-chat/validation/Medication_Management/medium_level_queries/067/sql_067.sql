WITH cohort AS (
  SELECT DISTINCT p.subject_id, a.hadm_id, a.admittime, a.dischtime
  FROM `physionet-data.mimiciv_3_1_hosp.patients` p
  JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a
    ON p.subject_id = a.subject_id
  JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d_dm
    ON a.hadm_id = d_dm.hadm_id
  JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` dd_dm
    ON d_dm.icd_code = dd_dm.icd_code
    AND d_dm.icd_version = dd_dm.icd_version
  JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d_hf
    ON a.hadm_id = d_hf.hadm_id
  JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` dd_hf
    ON d_hf.icd_code = dd_hf.icd_code
    AND d_hf.icd_version = dd_hf.icd_version
  WHERE p.gender = 'M'
    AND p.anchor_age BETWEEN 64 AND 74
    -- diabetes codes
    AND (
      (d_dm.icd_version = 9 AND d_dm.icd_code LIKE '250%')
      OR (d_dm.icd_version = 10 AND d_dm.icd_code LIKE 'E1%')
    )
    -- acute heart failure codes
    AND (
      (d_hf.icd_code LIKE '428%' AND LOWER(dd_hf.long_title) LIKE '%acute%')
      OR (d_hf.icd_code LIKE 'I50%' AND LOWER(dd_hf.long_title) LIKE '%acute%')
    )
),
drug_classes AS (
  SELECT 'Insulin' AS drug_class, 'insulin' AS pattern UNION ALL
  SELECT 'Metformin','metformin' UNION ALL
  SELECT 'Sulfonylureas','glyburide' UNION ALL
  SELECT 'Sulfonylureas','glipizide' UNION ALL
  SELECT 'Sulfonylureas','glimepiride' UNION ALL
  SELECT 'DPP4','sitagliptin' UNION ALL
  SELECT 'DPP4','saxagliptin' UNION ALL
  SELECT 'DPP4','linagliptin' UNION ALL
  SELECT 'DPP4','alogliptin' UNION ALL
  SELECT 'SGLT2','dapagliflozin' UNION ALL
  SELECT 'SGLT2','empagliflozin' UNION ALL
  SELECT 'SGLT2','canagliflozin' UNION ALL
  SELECT 'SGLT2','ertugliflozin' UNION ALL
  SELECT 'GLP1','liraglutide' UNION ALL
  SELECT 'GLP1','semaglutide' UNION ALL
  SELECT 'GLP1','exenatide' UNION ALL
  SELECT 'GLP1','dulaglutide' UNION ALL
  SELECT 'TZD','pioglitazone' UNION ALL
  SELECT 'TZD','rosiglitazone'
),
presc_matches AS (
  SELECT DISTINCT c.subject_id, c.hadm_id, dc.drug_class,
    CASE
      WHEN pr.starttime <= c.admittime + INTERVAL 12 HOUR THEN 'First 12h'
      WHEN pr.starttime >= c.dischtime - INTERVAL 48 HOUR THEN 'Final 48h'
      ELSE NULL
    END AS time_window
  FROM cohort c
  JOIN `physionet-data.mimiciv_3_1_hosp.prescriptions` pr
    ON c.hadm_id = pr.hadm_id
  JOIN drug_classes dc
    ON LOWER(pr.drug) LIKE CONCAT('%', dc.pattern, '%')
  WHERE pr.starttime IS NOT NULL
),
counts AS (
  SELECT drug_class, time_window, COUNT(DISTINCT subject_id) AS n_patients
  FROM presc_matches
  WHERE time_window IS NOT NULL
  GROUP BY drug_class, time_window
),
total AS (
  SELECT COUNT(DISTINCT subject_id) AS total_patients
  FROM cohort
)
SELECT
  c.drug_class,
  c.time_window,
  c.n_patients,
  t.total_patients,
  ROUND(100.0 * c.n_patients / t.total_patients, 2) AS pct_patients
FROM counts c
CROSS JOIN total t
ORDER BY drug_class, time_window;