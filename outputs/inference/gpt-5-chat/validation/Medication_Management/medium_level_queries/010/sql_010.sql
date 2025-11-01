WITH cohort AS (
  SELECT a.subject_id, a.hadm_id, p.gender, p.anchor_age, a.admittime, a.dischtime
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON a.subject_id = p.subject_id
  -- Female & age restriction
  WHERE p.gender = 'F'
    AND p.anchor_age BETWEEN 67 AND 77
),
dx AS (
  SELECT hadm_id,
    MAX(CASE WHEN (
      (icd_version = 9 AND icd_code LIKE '250%' AND (RIGHT(icd_code,1) IN ('0','2')))
      OR (icd_version = 10 AND icd_code LIKE 'E11%')
    ) THEN 1 ELSE 0 END) AS has_t2dm,
    MAX(CASE WHEN (
      (icd_version = 9 AND icd_code LIKE '428%')
      OR (icd_version = 10 AND icd_code LIKE 'I50%')
    ) THEN 1 ELSE 0 END) AS has_hf
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd`
  GROUP BY hadm_id
),
cohort_dx AS (
  SELECT c.*
  FROM cohort c
  JOIN dx d ON c.hadm_id = d.hadm_id
  WHERE d.has_t2dm = 1
    AND d.has_hf = 1
),
rx_class AS (
  SELECT pr.subject_id, pr.hadm_id, pr.starttime,
    CASE
      WHEN LOWER(pr.drug) LIKE '%insulin%' THEN 'Insulin'
      WHEN LOWER(pr.drug) LIKE '%metformin%' THEN 'Metformin'
      WHEN LOWER(pr.drug) LIKE '%glipizide%' OR LOWER(pr.drug) LIKE '%glyburide%' OR LOWER(pr.drug) LIKE '%glimepiride%' THEN 'Sulfonylurea'
      WHEN LOWER(pr.drug) LIKE '%sitagliptin%' OR LOWER(pr.drug) LIKE '%linagliptin%' OR LOWER(pr.drug) LIKE '%alogliptin%' OR LOWER(pr.drug) LIKE '%saxagliptin%' THEN 'DPP4'
      WHEN LOWER(pr.drug) LIKE '%canagliflozin%' OR LOWER(pr.drug) LIKE '%dapagliflozin%' OR LOWER(pr.drug) LIKE '%empagliflozin%' THEN 'SGLT2'
      WHEN LOWER(pr.drug) LIKE '%exenatide%' OR LOWER(pr.drug) LIKE '%liraglutide%' OR LOWER(pr.drug) LIKE '%dulaglutide%' OR LOWER(pr.drug) LIKE '%semaglutide%' THEN 'GLP1'
      WHEN LOWER(pr.drug) LIKE '%pioglitazone%' OR LOWER(pr.drug) LIKE '%rosiglitazone%' THEN 'TZD'
      ELSE NULL
    END AS drug_class
  FROM `physionet-data.mimiciv_3_1_hosp.prescriptions` pr
),
rx_window AS (
  SELECT cd.subject_id, cd.hadm_id, r.drug_class,
    CASE
      WHEN r.starttime BETWEEN cd.admittime AND DATETIME_ADD(cd.admittime, INTERVAL 12 HOUR) THEN 'first12h'
      WHEN r.starttime BETWEEN DATETIME_SUB(cd.dischtime, INTERVAL 48 HOUR) AND cd.dischtime THEN 'final48h'
      ELSE NULL
    END AS time_window
  FROM cohort_dx cd
  JOIN rx_class r
    ON cd.subject_id = r.subject_id
    AND cd.hadm_id = r.hadm_id
  WHERE r.drug_class IS NOT NULL
),
distinct_rx AS (
  SELECT DISTINCT subject_id, hadm_id, drug_class, time_window
  FROM rx_window
  WHERE time_window IS NOT NULL
),
counts AS (
  SELECT
    drug_class,
    SUM(CASE WHEN time_window = 'first12h' THEN 1 ELSE 0 END) AS pts_first12h,
    SUM(CASE WHEN time_window = 'final48h' THEN 1 ELSE 0 END) AS pts_final48h
  FROM distinct_rx
  GROUP BY drug_class
),
denominator AS (
  SELECT COUNT(DISTINCT hadm_id) AS n_patients
  FROM cohort_dx
)
SELECT
  c.drug_class,
  ROUND(100.0 * c.pts_first12h / d.n_patients, 2) AS pct_first12h,
  ROUND(100.0 * c.pts_final48h / d.n_patients, 2) AS pct_final48h,
  ROUND( (100.0 * c.pts_final48h / d.n_patients) -
         (100.0 * c.pts_first12h / d.n_patients), 2) AS net_change_pp
FROM counts c
CROSS JOIN denominator d
ORDER BY drug_class;