WITH cohort AS (
  SELECT
    p.subject_id,
    a.hadm_id,
    p.anchor_age,
    a.admittime,
    a.dischtime
  FROM
    `physionet-data.mimiciv_3_1_hosp.patients` p
  JOIN
    `physionet-data.mimiciv_3_1_hosp.admissions` a
  ON
    p.subject_id = a.subject_id
  WHERE
    p.gender = 'F'
    AND p.anchor_age BETWEEN 67 AND 77
),

diabetes_hf AS (
  SELECT DISTINCT
    c.subject_id,
    c.hadm_id
  FROM
    cohort c
  JOIN
    `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
  ON
    c.hadm_id = d.hadm_id
  JOIN
    `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` dd
  ON
    d.icd_code = dd.icd_code
    AND d.icd_version = dd.icd_version
  WHERE
    (dd.icd_code LIKE 'E11%' AND dd.icd_version = 10)
    OR (dd.icd_code LIKE 'I50%' AND dd.icd_version = 10)
  GROUP BY
    c.subject_id, c.hadm_id
  HAVING
    COUNT(DISTINCT CASE WHEN dd.icd_code LIKE 'E11%' THEN 1 END) > 0
    AND COUNT(DISTINCT CASE WHEN dd.icd_code LIKE 'I50%' THEN 1 END) > 0
),

drug_classified AS (
  SELECT
    dh.hadm_id,
    p.drug,
    p.starttime,
    c.admittime,
    c.dischtime,
    CASE
      WHEN LOWER(p.drug) LIKE '%insulin%' THEN 'Insulin'
      WHEN LOWER(p.drug) LIKE '%metformin%' THEN 'Metformin'
      WHEN LOWER(p.drug) LIKE '%glipizide%' OR LOWER(p.drug) LIKE '%glyburide%' THEN 'SU'
      WHEN LOWER(p.drug) LIKE '%sitagliptin%' OR LOWER(p.drug) LIKE '%saxagliptin%' THEN 'DPP-4'
      WHEN LOWER(p.drug) LIKE '%empagliflozin%' OR LOWER(p.drug) LIKE '%dapagliflozin%' THEN 'SGLT2'
      WHEN LOWER(p.drug) LIKE '%liraglutide%' OR LOWER(p.drug) LIKE '%semaglutide%' THEN 'GLP-1'
      WHEN LOWER(p.drug) LIKE '%pioglitazone%' THEN 'TZD'
      ELSE NULL
    END AS drug_class
  FROM
    diabetes_hf dh
  JOIN
    `physionet-data.mimiciv_3_1_hosp.prescriptions` p
  ON
    dh.hadm_id = p.hadm_id
  JOIN
    cohort c
  ON
    dh.hadm_id = c.hadm_id
  WHERE
    p.starttime IS NOT NULL
    AND p.drug IS NOT NULL
),

initiation_flags AS (
  SELECT
    hadm_id,
    drug_class,
    MAX(CASE WHEN starttime BETWEEN admittime AND admittime + INTERVAL 12 HOUR THEN 1 ELSE 0 END) AS init_first12h,
    MAX(CASE WHEN starttime BETWEEN dischtime - INTERVAL 48 HOUR AND dischtime THEN 1 ELSE 0 END) AS init_last48h
  FROM
    drug_classified
  WHERE
    drug_class IS NOT NULL
  GROUP BY
    hadm_id, drug_class
),

aggregated AS (
  SELECT
    drug_class,
    COUNT(DISTINCT hadm_id) AS total_patients,
    SUM(init_first12h) AS init_first12h_count,
    SUM(init_last48h) AS init_last48h_count
  FROM
    initiation_flags
  GROUP BY
    drug_class
)

SELECT
  drug_class,
  ROUND(SAFE_DIVIDE(init_first12h_count, total_patients) * 100, 2) AS init_first12h_pct,
  ROUND(SAFE_DIVIDE(init_last48h_count, total_patients) * 100, 2) AS init_last48h_pct,
  ROUND((SAFE_DIVIDE(init_last48h_count, total_patients) - SAFE_DIVIDE(init_first12h_count, total_patients)) * 100, 2) AS net_change_pp
FROM
  aggregated
ORDER BY
  drug_class;