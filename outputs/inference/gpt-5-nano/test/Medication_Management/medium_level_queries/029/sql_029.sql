WITH cohort AS (
  SELECT
    a.hadm_id,
    a.subject_id,
    a.admittime,
    a.dischtime,
    (p.anchor_age + (EXTRACT(YEAR FROM a.admittime) - p.anchor_year)) AS age_at_admit
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` AS a
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` AS p
    ON a.subject_id = p.subject_id
  WHERE a.dischtime IS NOT NULL
    AND p.gender = 'F'
    AND (p.anchor_age + (EXTRACT(YEAR FROM a.admittime) - p.anchor_year)) BETWEEN 69 AND 79
),
cohort_with_diagnosis AS (
  SELECT c.hadm_id
  FROM cohort AS c
  JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` AS di
    ON di.subject_id = c.subject_id AND di.hadm_id = c.hadm_id
  WHERE di.icd_code LIKE 'E11%' OR di.icd_code LIKE 'I50%'
  GROUP BY c.hadm_id
  HAVING SUM(CASE WHEN di.icd_code LIKE 'E11%' THEN 1 ELSE 0 END) > 0
     AND SUM(CASE WHEN di.icd_code LIKE 'I50%' THEN 1 ELSE 0 END) > 0
),
coh AS (
  SELECT c.hadm_id, c.admittime, c.dischtime
  FROM cohort AS c
  JOIN cohort_with_diagnosis AS cw ON c.hadm_id = cw.hadm_id
),
presc_flags AS (
  SELECT d.hadm_id,
         -- First 72h flags
         COALESCE(MAX(CASE
           WHEN LOWER(p.drug) LIKE '%insulin%'
                AND (p.starttime <= TIMESTAMP_ADD(d.admittime, INTERVAL 72 HOUR)
                     AND (p.stoptime IS NULL OR p.stoptime >= d.admittime))
           THEN 1 ELSE 0 END), 0) AS insulin_first72,
         COALESCE(MAX(CASE
           WHEN LOWER(p.drug) LIKE '%insulin%'
                AND (p.starttime <= d.dischtime
                     AND (p.stoptime IS NULL OR p.stoptime >= TIMESTAMP_SUB(d.dischtime, INTERVAL 72 HOUR)))
           THEN 1 ELSE 0 END), 0) AS insulin_last72,

         COALESCE(MAX(CASE
           WHEN LOWER(p.drug) LIKE '%metformin%'
                AND (p.starttime <= TIMESTAMP_ADD(d.admittime, INTERVAL 72 HOUR)
                     AND (p.stoptime IS NULL OR p.stoptime >= d.admittime))
           THEN 1 ELSE 0 END), 0) AS metformin_first72,
         COALESCE(MAX(CASE
           WHEN LOWER(p.drug) LIKE '%metformin%'
                AND (p.starttime <= d.dischtime
                     AND (p.stoptime IS NULL OR p.stoptime >= TIMESTAMP_SUB(d.dischtime, INTERVAL 72 HOUR)))
           THEN 1 ELSE 0 END), 0) AS metformin_last72,

         COALESCE(MAX(CASE
           WHEN ((LOWER(p.drug) LIKE '%glipizide%' OR LOWER(p.drug) LIKE '%glyburide%' OR LOWER(p.drug) LIKE '%glimepiride%' OR LOWER(p.drug) LIKE '%glibenclamide%'))
                AND (p.starttime <= TIMESTAMP_ADD(d.admittime, INTERVAL 72 HOUR)
                     AND (p.stoptime IS NULL OR p.stoptime >= d.admittime))
           THEN 1 ELSE 0 END), 0) AS sulfonyl_first72,
         COALESCE(MAX(CASE
           WHEN ((LOWER(p.drug) LIKE '%glipizide%' OR LOWER(p.drug) LIKE '%glyburide%' OR LOWER(p.drug) LIKE '%glimepiride%' OR LOWER(p.drug) LIKE '%glibenclamide%'))
                AND (p.starttime <= d.dischtime
                     AND (p.stoptime IS NULL OR p.stoptime >= TIMESTAMP_SUB(d.dischtime, INTERVAL 72 HOUR)))
           THEN 1 ELSE 0 END), 0) AS sulfonyl_last72,

         COALESCE(MAX(CASE
           WHEN ((LOWER(p.drug) LIKE '%sitagliptin%' OR LOWER(p.drug) LIKE '%saxagliptin%' OR LOWER(p.drug) LIKE '%linagliptin%' OR LOWER(p.drug) LIKE '%alogliptin%'))
                AND (p.starttime <= TIMESTAMP_ADD(d.admittime, INTERVAL 72 HOUR)
                     AND (p.stoptime IS NULL OR p.stoptime >= d.admittime))
           THEN 1 ELSE 0 END), 0) AS dpp4_first72,
         COALESCE(MAX(CASE
           WHEN ((LOWER(p.drug) LIKE '%sitagliptin%' OR LOWER(p.drug) LIKE '%saxagliptin%' OR LOWER(p.drug) LIKE '%linagliptin%' OR LOWER(p.drug) LIKE '%alogliptin%'))
                AND (p.starttime <= d.dischtime
                     AND (p.stoptime IS NULL OR p.stoptime >= TIMESTAMP_SUB(d.dischtime, INTERVAL 72 HOUR)))
           THEN 1 ELSE 0 END), 0) AS dpp4_last72,

         COALESCE(MAX(CASE
           WHEN ((LOWER(p.drug) LIKE '%canagliflozin%' OR LOWER(p.drug) LIKE '%dapagliflozin%' OR LOWER(p.drug) LIKE '%empagliflozin%' OR LOWER(p.drug) LIKE '%ertugliflozin%'))
                AND (p.starttime <= TIMESTAMP_ADD(d.admittime, INTERVAL 72 HOUR)
                     AND (p.stoptime IS NULL OR p.stoptime >= d.admittime))
           THEN 1 ELSE 0 END), 0) AS sglt2_first72,
         COALESCE(MAX(CASE
           WHEN ((LOWER(p.drug) LIKE '%canagliflozin%' OR LOWER(p.drug) LIKE '%dapagliflozin%' OR LOWER(p.drug) LIKE '%empagliflozin%' OR LOWER(p.drug) LIKE '%ertugliflozin%'))
                AND (p.starttime <= d.dischtime
                     AND (p.stoptime IS NULL OR p.stoptime >= TIMESTAMP_SUB(d.dischtime, INTERVAL 72 HOUR)))
           THEN 1 ELSE 0 END), 0) AS sglt2_last72,

         COALESCE(MAX(CASE
           WHEN ((LOWER(p.drug) LIKE '%liraglutide%' OR LOWER(p.drug) LIKE '%dulaglutide%' OR LOWER(p.drug) LIKE '%exenatide%' OR LOWER(p.drug) LIKE '%lixisenatide%' OR LOWER(p.drug) LIKE '%semaglutide%'))
                AND (p.starttime <= TIMESTAMP_ADD(d.admittime, INTERVAL 72 HOUR)
                     AND (p.stoptime IS NULL OR p.stoptime >= d.admittime))
           THEN 1 ELSE 0 END), 0) AS glp1_first72,
         COALESCE(MAX(CASE
           WHEN ((LOWER(p.drug) LIKE '%liraglutide%' OR LOWER(p.drug) LIKE '%dulaglutide%' OR LOWER(p.drug) LIKE '%exenatide%' OR LOWER(p.drug) LIKE '%lixisenatide%' OR LOWER(p.drug) LIKE '%semaglutide%'))
                AND (p.starttime <= d.dischtime
                     AND (p.stoptime IS NULL OR p.stoptime >= TIMESTAMP_SUB(d.dischtime, INTERVAL 72 HOUR)))
           THEN 1 ELSE 0 END), 0) AS glp1_last72,

         COALESCE(MAX(CASE
           WHEN ((LOWER(p.drug) LIKE '%pioglitazone%' OR LOWER(p.drug) LIKE '%rosiglitazone%'))
                AND (p.starttime <= TIMESTAMP_ADD(d.admittime, INTERVAL 72 HOUR)
                     AND (p.stoptime IS NULL OR p.stoptime >= d.admittime))
           THEN 1 ELSE 0 END), 0) AS tzd_first72,
         COALESCE(MAX(CASE
           WHEN ((LOWER(p.drug) LIKE '%pioglitazone%' OR LOWER(p.drug) LIKE '%rosiglitazone%'))
                AND (p.starttime <= d.dischtime
                     AND (p.stoptime IS NULL OR p.stoptime >= TIMESTAMP_SUB(d.dischtime, INTERVAL 72 HOUR)))
           THEN 1 ELSE 0 END), 0) AS tzd_last72
  FROM coh d
  LEFT JOIN `physionet-data.mimiciv_3_1_hosp.prescriptions` AS p
    ON p.hadm_id = d.hadm_id
  GROUP BY d.hadm_id
)
SELECT
  'insulin' AS drug_class,
  100.0 * SAFE_DIVIDE(SUM(insulin_first72), COUNT(*)) AS first72_pct,
  100.0 * SAFE_DIVIDE(SUM(insulin_last72), COUNT(*)) AS last72_pct
FROM presc_flags
UNION ALL
SELECT
  'metformin' AS drug_class,
  100.0 * SAFE_DIVIDE(SUM(metformin_first72), COUNT(*)) AS first72_pct,
  100.0 * SAFE_DIVIDE(SUM(metformin_last72), COUNT(*)) AS last72_pct
FROM presc_flags
UNION ALL
SELECT
  'sulfonylurea' AS drug_class,
  100.0 * SAFE_DIVIDE(SUM(sulfonyl_first72), COUNT(*)) AS first72_pct,
  100.0 * SAFE_DIVIDE(SUM(sulfonyl_last72), COUNT(*)) AS last72_pct
FROM presc_flags
UNION ALL
SELECT
  'DPP-4 inhibitors' AS drug_class,
  100.0 * SAFE_DIVIDE(SUM(dpp4_first72), COUNT(*)) AS first72_pct,
  100.0 * SAFE_DIVIDE(SUM(dpp4_last72), COUNT(*)) AS last72_pct
FROM presc_flags
UNION ALL
SELECT
  'SGLT2 inhibitors' AS drug_class,
  100.0 * SAFE_DIVIDE(SUM(sglt2_first72), COUNT(*)) AS first72_pct,
  100.0 * SAFE_DIVIDE(SUM(sglt2_last72), COUNT(*)) AS last72_pct
FROM presc_flags
UNION ALL
SELECT
  'GLP-1 receptor agonists' AS drug_class,
  100.0 * SAFE_DIVIDE(SUM(glp1_first72), COUNT(*)) AS first72_pct,
  100.0 * SAFE_DIVIDE(SUM(glp1_last72), COUNT(*)) AS last72_pct
FROM presc_flags
UNION ALL
SELECT
  'TZDs' AS drug_class,
  100.0 * SAFE_DIVIDE(SUM(tzd_first72), COUNT(*)) AS first72_pct,
  100.0 * SAFE_DIVIDE(SUM(tzd_last72), COUNT(*)) AS last72_pct
FROM presc_flags;