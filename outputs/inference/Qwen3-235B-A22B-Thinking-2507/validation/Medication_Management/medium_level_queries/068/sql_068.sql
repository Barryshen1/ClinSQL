WITH cohort AS (
  SELECT 
    adm.hadm_id,
    adm.subject_id,
    adm.admittime,
    adm.dischtime,
    p.anchor_age + (EXTRACT(YEAR FROM adm.admittime) - p.anchor_year) AS age_at_admission
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` adm
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON adm.subject_id = p.subject_id
  WHERE p.gender = 'F'
    AND p.anchor_age + (EXTRACT(YEAR FROM adm.admittime) - p.anchor_year) BETWEEN 83 AND 93
    AND EXISTS (
      SELECT 1 
      FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` diag
      WHERE diag.hadm_id = adm.hadm_id
        AND (
          (diag.icd_version = 9 AND diag.icd_code LIKE '250%' AND LENGTH(diag.icd_code) >= 5 AND SUBSTR(diag.icd_code, 5, 1) IN ('0','1'))
          OR (diag.icd_version = 10 AND diag.icd_code LIKE 'E11%')
        )
    )
    AND EXISTS (
      SELECT 1 
      FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` diag
      WHERE diag.hadm_id = adm.hadm_id
        AND (
          (diag.icd_version = 9 AND diag.icd_code LIKE '428%')
          OR (diag.icd_version = 10 AND diag.icd_code LIKE 'I50%')
        )
    )
),
insulin_orders AS (
  SELECT 
    c.hadm_id,
    c.subject_id,
    c.admittime,
    c.dischtime,
    p.starttime,
    CASE
      WHEN LOWER(p.drug) LIKE '%glargine%' OR LOWER(p.drug) LIKE '%detemir%' OR LOWER(p.drug) LIKE '%degludec%' OR LOWER(p.drug) LIKE '%nph%' THEN 'basal'
      WHEN LOWER(p.drug) LIKE '%aspart%' OR LOWER(p.drug) LIKE '%lispro%' OR LOWER(p.drug) LIKE '%regular%' OR LOWER(p.drug) LIKE '%glulisine%' THEN 'bolus'
      WHEN LOWER(p.drug) LIKE '%sliding scale%' THEN 'sliding_scale'
      ELSE NULL
    END AS insulin_type
  FROM cohort c
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.prescriptions` p
    ON c.hadm_id = p.hadm_id
  WHERE LOWER(p.drug) LIKE '%insulin%'
    AND p.starttime IS NOT NULL
),
first_occurrences AS (
  SELECT 
    hadm_id,
    insulin_type,
    MIN(starttime) AS first_time
  FROM insulin_orders
  WHERE insulin_type IS NOT NULL
  GROUP BY hadm_id, insulin_type
),
time_windows AS (
  SELECT 
    fo.hadm_id,
    fo.insulin_type,
    fo.first_time,
    CASE 
      WHEN fo.first_time BETWEEN c.admittime AND TIMESTAMP_ADD(c.admittime, INTERVAL 48 HOUR) 
      THEN 1 ELSE 0 
    END AS first_48h,
    CASE 
      WHEN fo.first_time BETWEEN TIMESTAMP_ADD(c.dischtime, INTERVAL -12 HOUR) AND c.dischtime 
      THEN 1 ELSE 0 
    END AS final_12h
  FROM first_occurrences fo
  INNER JOIN cohort c ON fo.hadm_id = c.hadm_id
),
aggregated AS (
  SELECT
    insulin_type,
    AVG(first_48h) AS pct_first_48h,
    AVG(final_12h) AS pct_final_12h,
    AVG(final_12h) - AVG(first_48h) AS net_change
  FROM time_windows
  GROUP BY insulin_type
)
SELECT
  'basal' AS insulin_regimen,
  COALESCE((SELECT pct_first_48h FROM aggregated WHERE insulin_type = 'basal'), 0) AS first_48h_pct,
  COALESCE((SELECT pct_final_12h FROM aggregated WHERE insulin_type = 'basal'), 0) AS final_12h_pct,
  COALESCE((SELECT net_change FROM aggregated WHERE insulin_type = 'basal'), 0) AS net_change
UNION ALL
SELECT
  'bolus',
  COALESCE((SELECT pct_first_48h FROM aggregated WHERE insulin_type = 'bolus'), 0),
  COALESCE((SELECT pct_final_12h FROM aggregated WHERE insulin_type = 'bolus'), 0),
  COALESCE((SELECT net_change FROM aggregated WHERE insulin_type = 'bolus'), 0)
UNION ALL
SELECT
  'basal-bolus',
  COALESCE((SELECT pct_first_48h FROM aggregated WHERE insulin_type = 'basal'), 0) * 
  COALESCE((SELECT pct_first_48h FROM aggregated WHERE insulin_type = 'bolus'), 0),
  COALESCE((SELECT pct_final_12h FROM aggregated WHERE insulin_type = 'basal'), 0) * 
  COALESCE((SELECT pct_final_12h FROM aggregated WHERE insulin_type = 'bolus'), 0),
  (COALESCE((SELECT pct_final_12h FROM aggregated WHERE insulin_type = 'basal'), 0) * 
   COALESCE((SELECT pct_final_12h FROM aggregated WHERE insulin_type = 'bolus'), 0)) -
  (COALESCE((SELECT pct_first_48h FROM aggregated WHERE insulin_type = 'basal'), 0) * 
   COALESCE((SELECT pct_first_48h FROM aggregated WHERE insulin_type = 'bolus'), 0))
UNION ALL
SELECT
  'sliding-scale',
  COALESCE((SELECT pct_first_48h FROM aggregated WHERE insulin_type = 'sliding_scale'), 0),
  COALESCE((SELECT pct_final_12h FROM aggregated WHERE insulin_type = 'sliding_scale'), 0),
  COALESCE((SELECT net_change FROM aggregated WHERE insulin_type = 'sliding_scale'), 0);