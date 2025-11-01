WITH patient_admissions AS (
  SELECT
    p.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    p.anchor_age,
    p.anchor_year,
    -- Compute age at admission
    (p.anchor_age + (EXTRACT(YEAR FROM a.admittime) - p.anchor_year)) AS age_at_admit
  FROM `physionet-data.mimiciv_3_1_hosp`.patients p
  INNER JOIN `physionet-data.mimiciv_3_1_hosp`.admissions a
    ON p.subject_id = a.subject_id
  WHERE p.gender = 'F'
    AND (p.anchor_age + (EXTRACT(YEAR FROM a.admittime) - p.anchor_year)) BETWEEN 68 AND 78
),
drug_exposure AS (
  SELECT
    pa.subject_id,
    pa.hadm_id,
    -- Metformin
    MAX(CASE WHEN LOWER(pr.drug) LIKE '%metformin%' THEN 1 ELSE 0 END) AS metformin_any,
    -- Sulfonylureas: common agents
    MAX(CASE WHEN LOWER(pr.drug) LIKE '%glyburide%' OR LOWER(pr.drug) LIKE '%glipizide%' OR LOWER(pr.drug) LIKE '%glimepiride%' THEN 1 ELSE 0 END) AS sulfonylurea_any,
    -- DPP-4 inhibitors
    MAX(CASE WHEN LOWER(pr.drug) LIKE '%sitagliptin%' OR LOWER(pr.drug) LIKE '%linagliptin%' OR LOWER(pr.drug) LIKE '%saxagliptin%' OR LOWER(pr.drug) LIKE '%alogliptin%' THEN 1 ELSE 0 END) AS dpp4_any,
    -- SGLT2 inhibitors
    MAX(CASE WHEN LOWER(pr.drug) LIKE '%empagliflozin%' OR LOWER(pr.drug) LIKE '%dapagliflozin%' OR LOWER(pr.drug) LIKE '%canagliflozin%' OR LOWER(pr.drug) LIKE '%ertugliflozin%' THEN 1 ELSE 0 END) AS sglt2_any,
    -- Time window flags
    MAX(CASE WHEN pr.starttime >= pa.admittime AND pr.starttime <= pa.admittime + INTERVAL '48' HOUR THEN 1 ELSE 0 END) AS in_first_48h,
    MAX(CASE WHEN pr.starttime >= pa.dischtime - INTERVAL '12' HOUR AND pr.starttime <= pa.dischtime THEN 1 ELSE 0 END) AS in_last_12h
  FROM patient_admissions pa
  LEFT JOIN `physionet-data.mimiciv_3_1_hosp`.prescriptions pr
    ON pa.subject_id = pr.subject_id AND pa.hadm_id = pr.hadm_id
  WHERE pr.drug IS NOT NULL
  GROUP BY pa.subject_id, pa.hadm_id, pa.admittime, pa.dischtime
),
drug_window_exposure AS (
  SELECT
    -- For each drug class, determine exposure in each window
    -- Metformin
    AVG(CASE WHEN metformin_any = 1 AND in_first_48h = 1 THEN 1.0 ELSE 0.0 END) AS metformin_first_48h,
    AVG(CASE WHEN metformin_any = 1 AND in_last_12h = 1 THEN 1.0 ELSE 0.0 END) AS metformin_last_12h,
    -- Sulfonylureas
    AVG(CASE WHEN sulfonylurea_any = 1 AND in_first_48h = 1 THEN 1.0 ELSE 0.0 END) AS sulfonylurea_first_48h,
    AVG(CASE WHEN sulfonylurea_any = 1 AND in_last_12h = 1 THEN 1.0 ELSE 0.0 END) AS sulfonylurea_last_12h,
    -- DPP-4
    AVG(CASE WHEN dpp4_any = 1 AND in_first_48h = 1 THEN 1.0 ELSE 0.0 END) AS dpp4_first_48h,
    AVG(CASE WHEN dpp4_any = 1 AND in_last_12h = 1 THEN 1.0 ELSE 0.0 END) AS dpp4_last_12h,
    -- SGLT2
    AVG(CASE WHEN sglt2_any = 1 AND in_first_48h = 1 THEN 1.0 ELSE 0.0 END) AS sglt2_first_48h,
    AVG(CASE WHEN sglt2_any = 1 AND in_last_12h = 1 THEN 1.0 ELSE 0.0 END) AS sglt2_last_12h
  FROM drug_exposure
)
-- Unpivot to get one row per drug class using UNION ALL
SELECT
  'Metformin' AS drug_class,
  ROUND(100 * metformin_first_48h, 2) AS first_48h_prevalence_pct,
  ROUND(100 * metformin_last_12h, 2) AS last_12h_prevalence_pct,
  ROUND(100 * (metformin_last_12h - metformin_first_48h), 2) AS net_change_pct
FROM drug_window_exposure

UNION ALL

SELECT
  'Sulfonylureas' AS drug_class,
  ROUND(100 * sulfonylurea_first_48h, 2) AS first_48h_prevalence_pct,
  ROUND(100 * sulfonylurea_last_12h, 2) AS last_12h_prevalence_pct,
  ROUND(100 * (sulfonylurea_last_12h - sulfonylurea_first_48h), 2) AS net_change_pct
FROM drug_window_exposure

UNION ALL

SELECT
  'DPP-4 inhibitors' AS drug_class,
  ROUND(100 * dpp4_first_48h, 2) AS first_48h_prevalence_pct,
  ROUND(100 * dpp4_last_12h, 2) AS last_12h_prevalence_pct,
  ROUND(100 * (dpp4_last_12h - dpp4_first_48h), 2) AS net_change_pct
FROM drug_window_exposure

UNION ALL

SELECT
  'SGLT2 inhibitors' AS drug_class,
  ROUND(100 * sglt2_first_48h, 2) AS first_48h_prevalence_pct,
  ROUND(100 * sglt2_last_12h, 2) AS last_12h_prevalence_pct,
  ROUND(100 * (sglt2_last_12h - sglt2_first_48h), 2) AS net_change_pct
FROM drug_window_exposure;