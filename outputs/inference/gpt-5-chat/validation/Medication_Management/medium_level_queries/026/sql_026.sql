WITH cohort AS (
  SELECT
    adm.subject_id,
    adm.hadm_id,
    adm.admittime,
    adm.dischtime
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` adm
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` pat
    ON adm.subject_id = pat.subject_id
  -- compute age at admission
  WHERE pat.gender = 'F'
    AND (pat.anchor_age + EXTRACT(YEAR FROM adm.admittime) - pat.anchor_year) BETWEEN 38 AND 48
    AND adm.hadm_id IN (
      -- admissions with T2D
      SELECT hadm_id
      FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd`
      WHERE ( (icd_version = 9 AND icd_code LIKE '250%')
           OR (icd_version = 10 AND icd_code LIKE 'E11%') )
    )
    AND adm.hadm_id IN (
      -- admissions with HF
      SELECT hadm_id
      FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd`
      WHERE ( (icd_version = 9 AND icd_code LIKE '428%')
           OR (icd_version = 10 AND icd_code LIKE 'I50%') )
    )
)
, rx_classified AS (
  SELECT
    c.hadm_id,
    CASE
      WHEN LOWER(pr.drug) LIKE '%insulin%' THEN 'insulin'
      WHEN LOWER(pr.drug) LIKE '%metformin%' THEN 'oral'
      WHEN LOWER(pr.drug) LIKE '%glipizide%' THEN 'oral'
      WHEN LOWER(pr.drug) LIKE '%glyburide%' THEN 'oral'
      WHEN LOWER(pr.drug) LIKE '%glimepiride%' THEN 'oral'
      WHEN LOWER(pr.drug) LIKE '%pioglitazone%' THEN 'oral'
      WHEN LOWER(pr.drug) LIKE '%rosiglitazone%' THEN 'oral'
      WHEN LOWER(pr.drug) LIKE '%sitagliptin%' THEN 'oral'
      WHEN LOWER(pr.drug) LIKE '%saxagliptin%' THEN 'oral'
      WHEN LOWER(pr.drug) LIKE '%linagliptin%' THEN 'oral'
      WHEN LOWER(pr.drug) LIKE '%alogliptin%' THEN 'oral'
      WHEN LOWER(pr.drug) LIKE '%canagliflozin%' THEN 'oral'
      WHEN LOWER(pr.drug) LIKE '%dapagliflozin%' THEN 'oral'
      WHEN LOWER(pr.drug) LIKE '%empagliflozin%' THEN 'oral'
      WHEN LOWER(pr.drug) LIKE '%repaglinide%' THEN 'oral'
      WHEN LOWER(pr.drug) LIKE '%nateglinide%' THEN 'oral'
      WHEN LOWER(pr.drug) LIKE '%acarbose%' THEN 'oral'
      WHEN LOWER(pr.drug) LIKE '%miglitol%' THEN 'oral'
      ELSE NULL
    END AS drug_class,
    pr.starttime
  FROM cohort c
  JOIN `physionet-data.mimiciv_3_1_hosp.prescriptions` pr
    ON c.hadm_id = pr.hadm_id
)
, window_flags AS (
  SELECT
    c.hadm_id,
    drug_class,
    MAX(CASE WHEN pr.starttime BETWEEN c.admittime AND DATETIME_ADD(c.admittime, INTERVAL 72 HOUR) THEN 1 ELSE 0 END) AS first72h_flag,
    MAX(CASE WHEN pr.starttime BETWEEN DATETIME_SUB(c.dischtime, INTERVAL 72 HOUR) AND c.dischtime THEN 1 ELSE 0 END) AS final72h_flag
  FROM cohort c
  JOIN rx_classified pr
    ON c.hadm_id = pr.hadm_id
  WHERE drug_class IS NOT NULL
  GROUP BY c.hadm_id, drug_class
)
, summary AS (
  SELECT
    drug_class,
    SUM(first72h_flag) AS first72h_count,
    SUM(final72h_flag) AS final72h_count
  FROM window_flags
  GROUP BY drug_class
)
SELECT
  drug_class,
  first72h_count,
  ROUND(100.0 * first72h_count / cohort_size, 2) AS first72h_pct,
  final72h_count,
  ROUND(100.0 * final72h_count / cohort_size, 2) AS final72h_pct
FROM summary
CROSS JOIN (
  SELECT COUNT(DISTINCT hadm_id) AS cohort_size FROM cohort
)
ORDER BY drug_class;