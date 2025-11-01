WITH cohort AS (
  SELECT 
    a.hadm_id,
    a.subject_id,
    a.admittime,
    a.dischtime,
    p.anchor_age
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` p 
    ON a.subject_id = p.subject_id
  WHERE 
    p.gender = 'F'
    AND p.anchor_age BETWEEN 65 AND 75
    AND a.dischtime IS NOT NULL
    AND TIMESTAMP_DIFF(a.dischtime, a.admittime, HOUR) >= 96
),
diag AS (
  SELECT 
    hadm_id,
    MAX(CASE WHEN 
          (icd_version = 10 AND (icd_code LIKE 'E08%' OR icd_code LIKE 'E09%' OR icd_code LIKE 'E10%' OR icd_code LIKE 'E11%' OR icd_code LIKE 'E12%' OR icd_code LIKE 'E13%')) 
          OR (icd_version = 9 AND icd_code LIKE '250%') 
        THEN 1 ELSE 0 END) AS has_diabetes,
    MAX(CASE WHEN 
          (icd_version = 10 AND icd_code LIKE 'I50%') 
          OR (icd_version = 9 AND icd_code LIKE '428%') 
        THEN 1 ELSE 0 END) AS has_hf
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd`
  GROUP BY hadm_id
),
cohort_final AS (
  SELECT c.*
  FROM cohort c
  INNER JOIN diag d ON c.hadm_id = d.hadm_id
  WHERE d.has_diabetes = 1 AND d.has_hf = 1
),
insulin_admin AS (
  SELECT 
    c.hadm_id,
    c.subject_id,
    c.admittime,
    c.dischtime,
    e.charttime,
    CASE 
      WHEN p.drug LIKE '%sliding scale%' THEN 'sliding-scale'
      WHEN p.drug LIKE '%glargine%' OR p.drug LIKE '%detemir%' OR p.drug LIKE '%degludec%' THEN 'basal'
      WHEN p.drug LIKE '%aspart%' OR p.drug LIKE '%lispro%' OR p.drug LIKE '%glulisine%' THEN 'bolus'
      WHEN p.drug LIKE '%70/30%' OR p.drug LIKE '%75/25%' OR p.drug LIKE '%50/50%' THEN 'basal-bolus'
      ELSE NULL 
    END AS insulin_type
  FROM cohort_final c
  LEFT JOIN `physionet-data.mimiciv_3_1_hosp.emar` e 
    ON c.subject_id = e.subject_id AND c.hadm_id = e.hadm_id
  LEFT JOIN `physionet-data.mimiciv_3_1_hosp.prescriptions` p 
    ON e.subject_id = p.subject_id AND e.hadm_id = p.hadm_id AND e.poe_id = p.poe_id
    AND p.drug LIKE '%insulin%'
),
time_flags AS (
  SELECT 
    hadm_id,
    insulin_type,
    MAX(CASE WHEN charttime BETWEEN admittime AND admittime + INTERVAL 48 HOUR THEN 1 ELSE 0 END) AS in_first_48h,
    MAX(CASE WHEN charttime BETWEEN dischtime - INTERVAL 48 HOUR AND dischtime THEN 1 ELSE 0 END) AS in_final_48h
  FROM insulin_admin
  WHERE insulin_type IS NOT NULL
  GROUP BY hadm_id, insulin_type
),
pivot_types AS (
  SELECT 
    hadm_id,
    MAX(CASE WHEN insulin_type = 'basal' THEN in_first_48h ELSE 0 END) AS basal_first,
    MAX(CASE WHEN insulin_type = 'basal' THEN in_final_48h ELSE 0 END) AS basal_final,
    MAX(CASE WHEN insulin_type = 'bolus' THEN in_first_48h ELSE 0 END) AS bolus_first,
    MAX(CASE WHEN insulin_type = 'bolus' THEN in_final_48h ELSE 0 END) AS bolus_final,
    MAX(CASE WHEN insulin_type = 'basal-bolus' THEN in_first_48h ELSE 0 END) AS basal_bolus_first,
    MAX(CASE WHEN insulin_type = 'basal-bolus' THEN in_final_48h ELSE 0 END) AS basal_bolus_final,
    MAX(CASE WHEN insulin_type = 'sliding-scale' THEN in_first_48h ELSE 0 END) AS sliding_scale_first,
    MAX(CASE WHEN insulin_type = 'sliding-scale' THEN in_final_48h ELSE 0 END) AS sliding_scale_final
  FROM time_flags
  GROUP BY hadm_id
),
type_summary AS (
  SELECT 
    'basal' AS insulin_type,
    SUM(basal_first) * 100.0 / COUNT(*) AS pct_first_48h,
    SUM(basal_final) * 100.0 / COUNT(*) AS pct_final_48h,
    SUM(CASE WHEN basal_first=1 AND basal_final=0 THEN 1 ELSE 0 END) * 100.0 / COUNT(*) AS pct_discontinued,
    SUM(CASE WHEN basal_first=0 AND basal_final=1 THEN 1 ELSE 0 END) * 100.0 / COUNT(*) AS pct_started_at_discharge
  FROM pivot_types
  UNION ALL
  SELECT 
    'bolus',
    SUM(bolus_first) * 100.0 / COUNT(*),
    SUM(bolus_final) * 100.0 / COUNT(*),
    SUM(CASE WHEN bolus_first=1 AND bolus_final=0 THEN 1 ELSE 0 END) * 100.0 / COUNT(*),
    SUM(CASE WHEN bolus_first=0 AND bolus_final=1 THEN 1 ELSE 0 END) * 100.0 / COUNT(*)
  FROM pivot_types
  UNION ALL
  SELECT 
    'basal-bolus',
    SUM(basal_bolus_first) * 100.0 / COUNT(*),
    SUM(basal_bolus_final) * 100.0 / COUNT(*),
    SUM(CASE WHEN basal_bolus_first=1 AND basal_bolus_final=0 THEN 1 ELSE 0 END) * 100.0 / COUNT(*),
    SUM(CASE WHEN basal_bolus_first=0 AND basal_bolus_final=1 THEN 1 ELSE 0 END) * 100.0 / COUNT(*)
  FROM pivot_types
  UNION ALL
  SELECT 
    'sliding-scale',
    SUM(sliding_scale_first) * 100.0 / COUNT(*),
    SUM(sliding_scale_final) * 100.0 / COUNT(*),
    SUM(CASE WHEN sliding_scale_first=1 AND sliding_scale_final=0 THEN 1 ELSE 0 END) * 100.0 / COUNT(*),
    SUM(CASE WHEN sliding_scale_first=0 AND sliding_scale_final=1 THEN 1 ELSE 0 END) * 100.0 / COUNT(*)
  FROM pivot_types
)
SELECT * FROM type_summary;