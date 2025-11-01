WITH
-- Step 1: Get patients with age 69-79 at admission and female gender
eligible_patients AS (
  SELECT
    p.subject_id,
    p.gender,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    -- Calculate age at admission
    p.anchor_age + (EXTRACT(YEAR FROM a.admittime) - p.anchor_year) AS age_at_admit
  FROM
    `physionet-data.mimiciv_3_1_hosp.patients` p
  INNER JOIN
    `physionet-data.mimiciv_3_1_hosp.admissions` a
  ON
    p.subject_id = a.subject_id
  WHERE
    p.gender = 'F'
    AND p.anchor_age + (EXTRACT(YEAR FROM a.admittime) - p.anchor_year) BETWEEN 69 AND 79
),

-- Step 2: Identify patients with T2DM
t2dm_diagnoses AS (
  SELECT DISTINCT
    d.hadm_id
  FROM
    `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
  WHERE
    (d.icd_version = 9 AND d.icd_code LIKE '250%' AND SUBSTR(d.icd_code, 4, 2) IN ('00','02','10','12','20','22','30','32','40','42','50','52','60','62','70','72','80','82','90','92'))
    OR (d.icd_version = 10 AND d.icd_code LIKE 'E11%')
),

-- Step 3: Identify patients with heart failure
hf_diagnoses AS (
  SELECT DISTINCT
    d.hadm_id
  FROM
    `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
  WHERE
    (d.icd_version = 9 AND d.icd_code LIKE '428%')
    OR (d.icd_version = 10 AND d.icd_code LIKE 'I50%')
),

-- Step 4: Get the final patient population (women 69-79 with T2DM and HF)
target_population AS (
  SELECT
    ep.subject_id,
    ep.hadm_id,
    ep.admittime,
    ep.dischtime
  FROM
    eligible_patients ep
  INNER JOIN
    t2dm_diagnoses t2dm
  ON
    ep.hadm_id = t2dm.hadm_id
  INNER JOIN
    hf_diagnoses hf
  ON
    ep.hadm_id = hf.hadm_id
),

-- Step 5: Identify drug administrations in first 72 hours
first_72_hours_drugs AS (
  SELECT
    tp.hadm_id,
    -- Drug class flags
    MAX(CASE WHEN e.medication LIKE '%insulin%' THEN 1 ELSE 0 END) AS insulin,
    MAX(CASE WHEN e.medication LIKE '%metformin%' THEN 1 ELSE 0 END) AS metformin,
    MAX(CASE WHEN e.medication LIKE '%glyburide%' OR e.medication LIKE '%glipizide%' OR e.medication LIKE '%glimepiride%' OR e.medication LIKE '%chlorpropamide%' OR e.medication LIKE '%tolazamide%' OR e.medication LIKE '%tolbutamide%' THEN 1 ELSE 0 END) AS sulfonylurea,
    MAX(CASE WHEN e.medication LIKE '%sitagliptin%' OR e.medication LIKE '%saxagliptin%' OR e.medication LIKE '%linagliptin%' OR e.medication LIKE '%alogliptin%' THEN 1 ELSE 0 END) AS dpp4,
    MAX(CASE WHEN e.medication LIKE '%canagliflozin%' OR e.medication LIKE '%dapagliflozin%' OR e.medication LIKE '%empagliflozin%' OR e.medication LIKE '%ertugliflozin%' THEN 1 ELSE 0 END) AS sglt2,
    MAX(CASE WHEN e.medication LIKE '%exenatide%' OR e.medication LIKE '%liraglutide%' OR e.medication LIKE '%dulaglutide%' OR e.medication LIKE '%semaglutide%' OR e.medication LIKE '%lixisenatide%' THEN 1 ELSE 0 END) AS glp1,
    MAX(CASE WHEN e.medication LIKE '%pioglitazone%' OR e.medication LIKE '%rosiglitazone%' THEN 1 ELSE 0 END) AS tzd
  FROM
    target_population tp
  LEFT JOIN
    `physionet-data.mimiciv_3_1_hosp.emar` e
  ON
    tp.hadm_id = e.hadm_id
    AND e.charttime >= tp.admittime
    AND e.charttime <= tp.admittime + INTERVAL 72 HOUR
  GROUP BY
    tp.hadm_id
),

-- Step 6: Identify drug administrations in last 72 hours
last_72_hours_drugs AS (
  SELECT
    tp.hadm_id,
    -- Drug class flags
    MAX(CASE WHEN e.medication LIKE '%insulin%' THEN 1 ELSE 0 END) AS insulin,
    MAX(CASE WHEN e.medication LIKE '%metformin%' THEN 1 ELSE 0 END) AS metformin,
    MAX(CASE WHEN e.medication LIKE '%glyburide%' OR e.medication LIKE '%glipizide%' OR e.medication LIKE '%glimepiride%' OR e.medication LIKE '%chlorpropamide%' OR e.medication LIKE '%tolazamide%' OR e.medication LIKE '%tolbutamide%' THEN 1 ELSE 0 END) AS sulfonylurea,
    MAX(CASE WHEN e.medication LIKE '%sitagliptin%' OR e.medication LIKE '%saxagliptin%' OR e.medication LIKE '%linagliptin%' OR e.medication LIKE '%alogliptin%' THEN 1 ELSE 0 END) AS dpp4,
    MAX(CASE WHEN e.medication LIKE '%canagliflozin%' OR e.medication LIKE '%dapagliflozin%' OR e.medication LIKE '%empagliflozin%' OR e.medication LIKE '%ertugliflozin%' THEN 1 ELSE 0 END) AS sglt2,
    MAX(CASE WHEN e.medication LIKE '%exenatide%' OR e.medication LIKE '%liraglutide%' OR e.medication LIKE '%dulaglutide%' OR e.medication LIKE '%semaglutide%' OR e.medication LIKE '%lixisenatide%' THEN 1 ELSE 0 END) AS glp1,
    MAX(CASE WHEN e.medication LIKE '%pioglitazone%' OR e.medication LIKE '%rosiglitazone%' THEN 1 ELSE 0 END) AS tzd
  FROM
    target_population tp
  LEFT JOIN
    `physionet-data.mimiciv_3_1_hosp.emar` e
  ON
    tp.hadm_id = e.hadm_id
    AND e.charttime >= tp.dischtime - INTERVAL 72 HOUR
    AND e.charttime <= tp.dischtime
  GROUP BY
    tp.hadm_id
)

-- Final result: percentages for each drug class in first and last 72 hours
SELECT
  -- First 72 hours percentages
  ROUND(100.0 * SUM(f.insulin) / COUNT(*), 2) AS insulin_first_72h_pct,
  ROUND(100.0 * SUM(f.metformin) / COUNT(*), 2) AS metformin_first_72h_pct,
  ROUND(100.0 * SUM(f.sulfonylurea) / COUNT(*), 2) AS sulfonylurea_first_72h_pct,
  ROUND(100.0 * SUM(f.dpp4) / COUNT(*), 2) AS dpp4_first_72h_pct,
  ROUND(100.0 * SUM(f.sglt2) / COUNT(*), 2) AS sglt2_first_72h_pct,
  ROUND(100.0 * SUM(f.glp1) / COUNT(*), 2) AS glp1_first_72h_pct,
  ROUND(100.0 * SUM(f.tzd) / COUNT(*), 2) AS tzd_first_72h_pct,
  -- Last 72 hours percentages
  ROUND(100.0 * SUM(l.insulin) / COUNT(*), 2) AS insulin_last_72h_pct,
  ROUND(100.0 * SUM(l.metformin) / COUNT(*), 2) AS metformin_last_72h_pct,
  ROUND(100.0 * SUM(l.sulfonylurea) / COUNT(*), 2) AS sulfonylurea_last_72h_pct,
  ROUND(100.0 * SUM(l.dpp4) / COUNT(*), 2) AS dpp4_last_72h_pct,
  ROUND(100.0 * SUM(l.sglt2) / COUNT(*), 2) AS sglt2_last_72h_pct,
  ROUND(100.0 * SUM(l.glp1) / COUNT(*), 2) AS glp1_last_72h_pct,
  ROUND(100.0 * SUM(l.tzd) / COUNT(*), 2) AS tzd_last_72h_pct
FROM
  first_72_hours_drugs f
INNER JOIN
  last_72_hours_drugs l
ON
  f.hadm_id = l.hadm_id;