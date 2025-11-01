WITH cohort AS (
  -- Select male patients aged 42-52 at admission
  SELECT
    a.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime
  FROM physionet-data.mimiciv_3_1_hosp.admissions a
  JOIN physionet-data.mimiciv_3_1_hosp.patients p
    ON a.subject_id = p.subject_id
  WHERE p.gender = 'M'
    AND p.anchor_age BETWEEN 42 AND 52
),
diabetes_admissions AS (
  -- Admissions with diabetes diagnosis
  SELECT DISTINCT hadm_id
  FROM physionet-data.mimiciv_3_1_hosp.diagnoses_icd d
  WHERE (
    (d.icd_version = 9 AND REGEXP_CONTAINS(d.icd_code, r'^250'))
    OR
    (d.icd_version = 10 AND REGEXP_CONTAINS(d.icd_code, r'^E0[89]|^E1[0-3]'))
  )
),
hf_admissions AS (
  -- Admissions with acute heart failure diagnosis
  SELECT DISTINCT hadm_id
  FROM physionet-data.mimiciv_3_1_hosp.diagnoses_icd d
  WHERE (
    (d.icd_version = 9 AND (
      REGEXP_CONTAINS(d.icd_code, r'^4280$|^4281$|^4282[0-3]$|^4283[0-3]$|^4284[0-3]$')
    ))
    OR
    (d.icd_version = 10 AND (
      REGEXP_CONTAINS(d.icd_code, r'^I50')
    ))
  )
),
target_admissions AS (
  -- Admissions with both diabetes and acute HF
  SELECT c.subject_id, c.hadm_id, c.admittime, c.dischtime
  FROM cohort c
  JOIN diabetes_admissions d ON c.hadm_id = d.hadm_id
  JOIN hf_admissions h ON c.hadm_id = h.hadm_id
),
drug_classes AS (
  -- Map drugs to antidiabetic classes
  SELECT
    hadm_id,
    starttime,
    LOWER(drug) AS drug_lower,
    CASE
      WHEN LOWER(drug) LIKE '%insulin%' THEN 'Insulin'
      WHEN LOWER(drug) LIKE '%metformin%' THEN 'Metformin'
      WHEN LOWER(drug) LIKE '%glyburide%' OR LOWER(drug) LIKE '%glipizide%' OR LOWER(drug) LIKE '%glimepiride%'
        OR LOWER(drug) LIKE '%tolbutamide%' OR LOWER(drug) LIKE '%chlorpropamide%' OR LOWER(drug) LIKE '%tolazamide%' THEN 'Sulfonylurea'
      WHEN LOWER(drug) LIKE '%sitagliptin%' OR LOWER(drug) LIKE '%saxagliptin%' OR LOWER(drug) LIKE '%linagliptin%' OR LOWER(drug) LIKE '%alogliptin%' THEN 'DPP-4'
      WHEN LOWER(drug) LIKE '%canagliflozin%' OR LOWER(drug) LIKE '%dapagliflozin%' OR LOWER(drug) LIKE '%empagliflozin%' OR LOWER(drug) LIKE '%ertugliflozin%' THEN 'SGLT2'
      WHEN LOWER(drug) LIKE '%exenatide%' OR LOWER(drug) LIKE '%liraglutide%' OR LOWER(drug) LIKE '%dulaglutide%' OR LOWER(drug) LIKE '%semaglutide%' OR LOWER(drug) LIKE '%albiglutide%' OR LOWER(drug) LIKE '%lixisenatide%' THEN 'GLP-1'
      WHEN LOWER(drug) LIKE '%pioglitazone%' OR LOWER(drug) LIKE '%rosiglitazone%' THEN 'TZD'
      ELSE NULL
    END AS drug_class
  FROM physionet-data.mimiciv_3_1_hosp.prescriptions
),
window_exposure AS (
  -- For each admission, drug class, and window, flag exposure
  SELECT
    ta.hadm_id,
    dc.drug_class,
    -- First 24h window
    MAX(CASE WHEN dc.starttime >= ta.admittime AND dc.starttime < DATETIME_ADD(ta.admittime, INTERVAL 24 HOUR) THEN 1 ELSE 0 END) AS exposed_first24h,
    -- Final 12h window
    MAX(CASE WHEN dc.starttime >= DATETIME_SUB(ta.dischtime, INTERVAL 12 HOUR) AND dc.starttime < ta.dischtime THEN 1 ELSE 0 END) AS exposed_final12h
  FROM target_admissions ta
  JOIN drug_classes dc ON ta.hadm_id = dc.hadm_id
  WHERE dc.drug_class IS NOT NULL
  GROUP BY ta.hadm_id, dc.drug_class
),
admission_counts AS (
  -- Number of admissions in cohort
  SELECT COUNT(DISTINCT hadm_id) AS n_admissions FROM target_admissions
),
class_prevalence AS (
  -- Calculate prevalence per class and window
  SELECT
    dc.drug_class,
    SUM(exposed_first24h) AS n_first24h,
    SUM(exposed_final12h) AS n_final12h
  FROM window_exposure dc
  GROUP BY dc.drug_class
),
final AS (
  SELECT
    cp.drug_class,
    ROUND(100.0 * cp.n_first24h / ac.n_admissions, 2) AS pct_first24h,
    ROUND(100.0 * cp.n_final12h / ac.n_admissions, 2) AS pct_final12h,
    ROUND(100.0 * (cp.n_final12h - cp.n_first24h) / ac.n_admissions, 2) AS net_change_pp
  FROM class_prevalence cp
  CROSS JOIN admission_counts ac
)
SELECT
  drug_class,
  pct_first24h,
  pct_final12h,
  net_change_pp
FROM final
ORDER BY drug_class;