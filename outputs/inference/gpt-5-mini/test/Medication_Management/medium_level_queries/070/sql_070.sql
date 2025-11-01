WITH
-- Diagnosis descriptions joined to coded diagnoses
diag_enriched AS (
  SELECT
    d.subject_id,
    d.hadm_id,
    d.icd_code,
    d.icd_version,
    LOWER(COALESCE(dd.long_title, '')) AS long_title
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
  LEFT JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` dd
    ON d.icd_code = dd.icd_code
    AND d.icd_version = dd.icd_version
),
-- Flag admissions that have T2DM and HF diagnoses (per hadm_id)
diag_flags AS (
  SELECT
    hadm_id,
    MAX(
      CASE
        -- T2DM: ICD-10 E11* or ICD-9 250* OR textual hints for type 2 diabetes
        WHEN icd_code LIKE 'E11%' OR icd_code LIKE '250%' 
          OR (long_title LIKE '%diabetes%' AND (long_title LIKE '%type 2%' OR long_title LIKE '%type ii%'))
        THEN 1 ELSE 0 END) AS has_t2dm,
    MAX(
      CASE
        -- Heart failure: ICD-10 I50* or ICD-9 428* OR textual hints 'heart failure'
        WHEN icd_code LIKE 'I50%' OR icd_code LIKE '428%' OR long_title LIKE '%heart failure%'
        THEN 1 ELSE 0 END) AS has_hf
  FROM diag_enriched
  GROUP BY hadm_id
),
-- Cohort: female patients aged 68-78 with admissions that have both T2DM and HF
cohort AS (
  SELECT
    a.hadm_id,
    a.subject_id,
    a.admittime,
    a.dischtime
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON a.subject_id = p.subject_id
  JOIN diag_flags df
    ON a.hadm_id = df.hadm_id
  WHERE
    p.gender = 'F'
    AND p.anchor_age BETWEEN 68 AND 78
    AND df.has_t2dm = 1
    AND df.has_hf = 1
    AND a.dischtime IS NOT NULL
),
-- Union medication records from prescriptions, pharmacy, emar
meds_union AS (
  -- prescriptions (orders)
  SELECT
    hadm_id,
    SAFE_CAST(starttime AS DATETIME) AS event_ts,
    LOWER(COALESCE(drug, '')) AS drug_text,
    'prescription' AS source
  FROM `physionet-data.mimiciv_3_1_hosp.prescriptions`
  WHERE hadm_id IS NOT NULL

  UNION ALL

  -- pharmacy (dispensations)
  SELECT
    hadm_id,
    SAFE_CAST(starttime AS DATETIME) AS event_ts,
    LOWER(COALESCE(medication, '')) AS drug_text,
    'pharmacy' AS source
  FROM `physionet-data.mimiciv_3_1_hosp.pharmacy`
  WHERE hadm_id IS NOT NULL

  UNION ALL

  -- emar (medication administrations/orders)
  SELECT
    hadm_id,
    SAFE_CAST(charttime AS DATETIME) AS event_ts,
    LOWER(COALESCE(medication, '')) AS drug_text,
    'emar' AS source
  FROM `physionet-data.mimiciv_3_1_hosp.emar`
  WHERE hadm_id IS NOT NULL
),
-- Keep only med records for admissions in our cohort and classify into drug classes
meds_classified AS (
  SELECT
    m.hadm_id,
    m.event_ts,
    m.drug_text,
    CASE
      WHEN m.drug_text LIKE '%metformin%' THEN 'metformin'
      WHEN m.drug_text LIKE '%glipizide%' THEN 'sulfonylurea'
      WHEN m.drug_text LIKE '%glyburide%' THEN 'sulfonylurea'
      WHEN m.drug_text LIKE '%glimepiride%' THEN 'sulfonylurea'
      WHEN m.drug_text LIKE '%tolbutamide%' THEN 'sulfonylurea'
      WHEN m.drug_text LIKE '%chlorpropamide%' THEN 'sulfonylurea'
      WHEN m.drug_text LIKE '%sitagliptin%' THEN 'dpp4'
      WHEN m.drug_text LIKE '%saxagliptin%' THEN 'dpp4'
      WHEN m.drug_text LIKE '%linagliptin%' THEN 'dpp4'
      WHEN m.drug_text LIKE '%alogliptin%' THEN 'dpp4'
      WHEN m.drug_text LIKE '%vildagliptin%' THEN 'dpp4'
      WHEN m.drug_text LIKE '%empagliflozin%' THEN 'sglt2'
      WHEN m.drug_text LIKE '%canagliflozin%' THEN 'sglt2'
      WHEN m.drug_text LIKE '%dapagliflozin%' THEN 'sglt2'
      WHEN m.drug_text LIKE '%ertugliflozin%' THEN 'sglt2'
      ELSE NULL
    END AS med_class
  FROM meds_union m
  JOIN cohort c
    ON m.hadm_id = c.hadm_id
  WHERE m.event_ts IS NOT NULL -- need a timestamp to place into windows
    AND (
      m.drug_text LIKE '%metformin%'
      OR m.drug_text LIKE '%glipizide%'
      OR m.drug_text LIKE '%glyburide%'
      OR m.drug_text LIKE '%glimepiride%'
      OR m.drug_text LIKE '%tolbutamide%'
      OR m.drug_text LIKE '%chlorpropamide%'
      OR m.drug_text LIKE '%sitagliptin%'
      OR m.drug_text LIKE '%saxagliptin%'
      OR m.drug_text LIKE '%linagliptin%'
      OR m.drug_text LIKE '%alogliptin%'
      OR m.drug_text LIKE '%vildagliptin%'
      OR m.drug_text LIKE '%empagliflozin%'
      OR m.drug_text LIKE '%canagliflozin%'
      OR m.drug_text LIKE '%dapagliflozin%'
      OR m.drug_text LIKE '%ertugliflozin%'
    )
),
-- For each admission and med class, determine if there was at least one exposure in each window
per_admission_class_flags AS (
  SELECT
    c.hadm_id,
    mc.med_class,
    MAX(CASE
          WHEN mc.event_ts BETWEEN c.admittime AND DATETIME_ADD(c.admittime, INTERVAL 48 HOUR) THEN 1
          ELSE 0 END) AS any_first48,
    MAX(CASE
          WHEN mc.event_ts BETWEEN DATETIME_SUB(c.dischtime, INTERVAL 12 HOUR) AND c.dischtime THEN 1
          ELSE 0 END) AS any_last12
  FROM cohort c
  LEFT JOIN meds_classified mc
    ON c.hadm_id = mc.hadm_id
  WHERE mc.med_class IS NOT NULL
  GROUP BY c.hadm_id, mc.med_class
),
-- Ensure we have rows for classes even if some admissions had zero exposures (so we can count denominators correctly)
classes AS (
  SELECT 'metformin' AS med_class UNION ALL
  SELECT 'sulfonylurea' UNION ALL
  SELECT 'dpp4' UNION ALL
  SELECT 'sglt2'
),
-- Aggregate counts across admissions to compute prevalence
aggregate_by_class AS (
  SELECT
    cl.med_class,
    COUNT(DISTINCT CASE WHEN paf.any_first48 = 1 THEN paf.hadm_id END) AS n_first48,
    COUNT(DISTINCT CASE WHEN paf.any_last12 = 1 THEN paf.hadm_id END) AS n_last12
  FROM classes cl
  LEFT JOIN per_admission_class_flags paf
    ON cl.med_class = paf.med_class
  GROUP BY cl.med_class
),
denom AS (
  SELECT COUNT(DISTINCT hadm_id) AS n_admissions FROM cohort
)
SELECT
  a.med_class AS medication_class,
  denom.n_admissions AS admissions_in_cohort,
  a.n_first48 AS count_first48h,
  ROUND(SAFE_DIVIDE(a.n_first48, denom.n_admissions) * 100, 2) AS pct_first48h,
  a.n_last12 AS count_last12h,
  ROUND(SAFE_DIVIDE(a.n_last12, denom.n_admissions) * 100, 2) AS pct_last12h,
  ROUND( (SAFE_DIVIDE(a.n_last12, denom.n_admissions) * 100)
         - (SAFE_DIVIDE(a.n_first48, denom.n_admissions) * 100), 2) AS pct_point_change_last12_minus_first48
FROM aggregate_by_class a
CROSS JOIN denom
ORDER BY medication_class;