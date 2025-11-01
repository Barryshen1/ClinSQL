WITH
-- Primary (index) diagnosis per admission: identify MI admissions and classify as STEMI vs NSTEMI
primary_mi AS (
  SELECT
    a.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    a.hospital_expire_flag,
    p.anchor_age,
    p.gender,
    LOWER(COALESCE(diag.long_title, '')) AS primary_long_title,
    d.icd_code,
    d.icd_version,
    -- classify MI type using ICD-10 codes when explicit, or text matching otherwise
    CASE
      -- ICD-10 explicit code patterns
      WHEN d.icd_version = 10 AND (STARTS_WITH(d.icd_code, 'I21.0') OR STARTS_WITH(d.icd_code, 'I21.1') OR STARTS_WITH(d.icd_code, 'I21.2') OR STARTS_WITH(d.icd_code, 'I21.3')) THEN 'STEMI'
      WHEN d.icd_version = 10 AND STARTS_WITH(d.icd_code, 'I21.4') THEN 'NSTEMI'
      -- textual indications for STEMI
      WHEN LOWER(COALESCE(diag.long_title, '')) LIKE '%st elevation%' OR LOWER(COALESCE(diag.long_title, '')) LIKE '%stemi%' THEN 'STEMI'
      -- textual indications for NSTEMI / non-ST
      WHEN LOWER(COALESCE(diag.long_title, '')) LIKE '%non-st%' OR LOWER(COALESCE(diag.long_title, '')) LIKE '%non st%' OR LOWER(COALESCE(diag.long_title, '')) LIKE '%nstemi%' OR LOWER(COALESCE(diag.long_title, '')) LIKE '%nonstemi%' OR LOWER(COALESCE(diag.long_title, '')) LIKE '%non q wave%' THEN 'NSTEMI'
      ELSE NULL
    END AS mi_type
  FROM
    `physionet-data.mimiciv_3_1_hosp.admissions` a
    JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
      ON a.subject_id = p.subject_id
    JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
      ON a.hadm_id = d.hadm_id
    LEFT JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` diag
      ON d.icd_code = diag.icd_code AND d.icd_version = diag.icd_version
  WHERE
    p.gender = 'M'
    AND p.anchor_age BETWEEN 51 AND 61
    AND d.seq_num = 1 -- primary diagnosis
),
-- For each admission, compute LOS days, LOS bin; only keep admissions we classified as STEMI or NSTEMI
mi_cohort AS (
  SELECT
    pm.*,
    -- LOS in days: ceiling of seconds/86400, minimum 1
    GREATEST(1, CAST(CEIL(SAFE_DIVIDE(TIMESTAMP_DIFF(pm.dischtime, pm.admittime, SECOND), 86400.0)) AS INT64)) AS los_days,
    CASE
      WHEN GREATEST(1, CAST(CEIL(SAFE_DIVIDE(TIMESTAMP_DIFF(pm.dischtime, pm.admittime, SECOND), 86400.0)) AS INT64)) BETWEEN 1 AND 2 THEN '1-2'
      WHEN GREATEST(1, CAST(CEIL(SAFE_DIVIDE(TIMESTAMP_DIFF(pm.dischtime, pm.admittime, SECOND), 86400.0)) AS INT64)) BETWEEN 3 AND 5 THEN '3-5'
      WHEN GREATEST(1, CAST(CEIL(SAFE_DIVIDE(TIMESTAMP_DIFF(pm.dischtime, pm.admittime, SECOND), 86400.0)) AS INT64)) BETWEEN 6 AND 9 THEN '6-9'
      ELSE '>=10'
    END AS los_bin
  FROM primary_mi pm
  WHERE pm.mi_type IS NOT NULL
),
-- Compute per-admission comorbidity count (excluding MI diagnoses) and flags for CKD and diabetes
hadm_comorb AS (
  SELECT
    d.hadm_id,
    COUNT(DISTINCT CASE
        WHEN LOWER(COALESCE(diag.long_title, '')) LIKE '%myocardial infarction%' THEN NULL
        WHEN LOWER(COALESCE(diag.long_title, '')) LIKE '%acute myocardial%' THEN NULL
        WHEN d.icd_code IS NULL THEN NULL
        ELSE d.icd_code
      END) AS comorb_count,
    -- CKD if any diagnosis text/code indicates chronic kidney disease
    MAX(CASE
      WHEN LOWER(COALESCE(diag.long_title, '')) LIKE '%chronic kidney%' THEN 1
      WHEN LOWER(COALESCE(diag.long_title, '')) LIKE '%chronic renal%' THEN 1
      WHEN LOWER(COALESCE(diag.long_title, '')) LIKE '%ckd%' THEN 1
      WHEN d.icd_version = 10 AND STARTS_WITH(d.icd_code, 'N18') THEN 1
      WHEN d.icd_version = 9 AND (STARTS_WITH(d.icd_code, '585') OR LOWER(COALESCE(diag.long_title, '')) LIKE '%chronic kidney%') THEN 1
      ELSE 0
    END) AS has_ckd,
    -- Diabetes if any diagnosis mentions diabetes
    MAX(CASE
      WHEN LOWER(COALESCE(diag.long_title, '')) LIKE '%diabetes%' THEN 1
      WHEN d.icd_version = 10 AND (STARTS_WITH(d.icd_code, 'E10') OR STARTS_WITH(d.icd_code, 'E11') OR STARTS_WITH(d.icd_code, 'E08') OR STARTS_WITH(d.icd_code, 'E09') OR STARTS_WITH(d.icd_code, 'E13')) THEN 1
      WHEN d.icd_version = 9 AND (STARTS_WITH(d.icd_code, '250') OR LOWER(COALESCE(diag.long_title, '')) LIKE '%diabetes%') THEN 1
      ELSE 0
    END) AS has_diabetes
  FROM
    `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
    LEFT JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` diag
      ON d.icd_code = diag.icd_code AND d.icd_version = diag.icd_version
  GROUP BY
    d.hadm_id
),
-- Combine cohort with comorbidity info
cohort_with_comorb AS (
  SELECT
    m.hadm_id,
    m.subject_id,
    m.admittime,
    m.dischtime,
    m.hospital_expire_flag,
    m.anchor_age,
    m.gender,
    m.mi_type,
    m.los_days,
    m.los_bin,
    COALESCE(hc.comorb_count, 0) AS comorb_count,
    CASE
      WHEN COALESCE(hc.comorb_count, 0) <= 1 THEN '0-1'
      WHEN COALESCE(hc.comorb_count, 0) = 2 THEN '2'
      ELSE '>=3'
    END AS comorb_group,
    COALESCE(hc.has_ckd, 0) AS has_ckd,
    COALESCE(hc.has_diabetes, 0) AS has_diabetes
  FROM mi_cohort m
  LEFT JOIN hadm_comorb hc
    ON m.hadm_id = hc.hadm_id
)
-- Final aggregation by MI type, LOS bin, and comorbidity group
SELECT
  mi_type AS MI_type,
  los_bin AS LOS_bin,
  comorb_group AS Comorbidity_group,
  COUNT(*) AS N,
  ROUND(100.0 * SUM(CASE WHEN hospital_expire_flag = 1 THEN 1 ELSE 0 END) / COUNT(*), 1) AS in_hospital_mortality_pct,
  ROUND(100.0 * SUM(has_ckd) / COUNT(*), 1) AS CKD_prevalence_pct,
  ROUND(100.0 * SUM(has_diabetes) / COUNT(*), 1) AS Diabetes_prevalence_pct
FROM cohort_with_comorb
GROUP BY
  mi_type, los_bin, comorb_group
ORDER BY
  mi_type,
  -- order LOS bins logically
  CASE los_bin WHEN '1-2' THEN 1 WHEN '3-5' THEN 2 WHEN '6-9' THEN 3 ELSE 4 END,
  CASE comorb_group WHEN '0-1' THEN 1 WHEN '2' THEN 2 ELSE 3 END;