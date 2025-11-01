WITH cohort AS (
  SELECT 
    a.hadm_id,
    a.admittime,
    a.dischtime
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` p 
    ON a.subject_id = p.subject_id
  -- Diabetes diagnosis (ICD-10 codes E08-E13)
  INNER JOIN (
    SELECT hadm_id
    FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd`
    WHERE icd_version = 10
      AND (icd_code LIKE 'E08%' 
           OR icd_code LIKE 'E09%' 
           OR icd_code LIKE 'E10%' 
           OR icd_code LIKE 'E11%' 
           OR icd_code LIKE 'E13%')
    GROUP BY hadm_id
  ) diabetes ON a.hadm_id = diabetes.hadm_id
  -- Acute heart failure diagnosis (ICD-10 codes I502/I503/I504)
  INNER JOIN (
    SELECT hadm_id
    FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd`
    WHERE icd_version = 10
      AND (icd_code LIKE 'I502%' 
           OR icd_code LIKE 'I503%' 
           OR icd_code LIKE 'I504%')
    GROUP BY hadm_id
  ) ahf ON a.hadm_id = ahf.hadm_id
  WHERE p.gender = 'M'
    -- Age at admission: 51-61 inclusive
    AND (p.anchor_age + (EXTRACT(YEAR FROM a.admittime) - p.anchor_year)) BETWEEN 51 AND 61
),
first_24h AS (
  SELECT 
    c.hadm_id,
    COALESCE(MAX(CASE WHEN p.medication IN (
        'Insulin Glargine', 
        'Insulin Detemir', 
        'Insulin Degludec', 
        'Insulin NPH', 
        'Insulin NPH Human', 
        'Insulin Protamine (NPH)',
        'Insulin Glargine [Lantus]',
        'Insulin Glargine [Toujeo]',
        'Insulin Detemir [Levemir]',
        'Insulin Degludec [Tresiba]'
      ) THEN 1 ELSE 0 END), 0) AS has_basal,
    COALESCE(MAX(CASE WHEN p.medication IN (
        'Insulin Aspart', 
        'Insulin Lispro', 
        'Insulin Regular', 
        'Regular Insulin', 
        'Insulin, Regular', 
        'Insulin Aspart [NovoLog]',
        'Insulin Lispro [Humalog]',
        'Insulin Regular [Humulin R]'
      ) AND (p.sliding_scale = 'NO' OR p.sliding_scale IS NULL) THEN 1 ELSE 0 END), 0) AS has_fixed_bolus,
    COALESCE(MAX(CASE WHEN p.sliding_scale = 'YES' THEN 1 ELSE 0 END), 0) AS has_sliding_scale
  FROM cohort c
  LEFT JOIN `physionet-data.mimiciv_3_1_hosp.pharmacy` p
    ON c.hadm_id = p.hadm_id
    AND p.starttime >= c.admittime 
    AND p.starttime < c.admittime + INTERVAL '24' HOUR
  GROUP BY c.hadm_id
),
final_12h AS (
  SELECT 
    c.hadm_id,
    COALESCE(MAX(CASE WHEN p.medication IN (
        'Insulin Glargine', 
        'Insulin Detemir', 
        'Insulin Degludec', 
        'Insulin NPH', 
        'Insulin NPH Human', 
        'Insulin Protamine (NPH)',
        'Insulin Glargine [Lantus]',
        'Insulin Glargine [Toujeo]',
        'Insulin Detemir [Levemir]',
        'Insulin Degludec [Tresiba]'
      ) THEN 1 ELSE 0 END), 0) AS has_basal,
    COALESCE(MAX(CASE WHEN p.medication IN (
        'Insulin Aspart', 
        'Insulin Lispro', 
        'Insulin Regular', 
        'Regular Insulin', 
        'Insulin, Regular', 
        'Insulin Aspart [NovoLog]',
        'Insulin Lispro [Humalog]',
        'Insulin Regular [Humulin R]'
      ) AND (p.sliding_scale = 'NO' OR p.sliding_scale IS NULL) THEN 1 ELSE 0 END), 0) AS has_fixed_bolus,
    COALESCE(MAX(CASE WHEN p.sliding_scale = 'YES' THEN 1 ELSE 0 END), 0) AS has_sliding_scale
  FROM cohort c
  LEFT JOIN `physionet-data.mimiciv_3_1_hosp.pharmacy` p
    ON c.hadm_id = p.hadm_id
    AND p.starttime >= c.dischtime - INTERVAL '12' HOUR
    AND p.starttime < c.dischtime
  GROUP BY c.hadm_id
),
flags AS (
  SELECT 
    c.hadm_id,
    -- First 24h flags
    f24.has_basal * f24.has_fixed_bolus AS basal_bolus_24h,
    f24.has_basal * (1 - f24.has_fixed_bolus) * (1 - f24.has_sliding_scale) AS basal_24h,
    (1 - f24.has_basal) * f24.has_fixed_bolus AS bolus_24h,
    f24.has_sliding_scale AS sliding_scale_24h,
    -- Final 12h flags
    f12.has_basal * f12.has_fixed_bolus AS basal_bolus_12h,
    f12.has_basal * (1 - f12.has_fixed_bolus) * (1 - f12.has_sliding_scale) AS basal_12h,
    (1 - f12.has_basal) * f12.has_fixed_bolus AS bolus_12h,
    f12.has_sliding_scale AS sliding_scale_12h
  FROM cohort c
  LEFT JOIN first_24h f24 ON c.hadm_id = f24.hadm_id
  LEFT JOIN final_12h f12 ON c.hadm_id = f12.hadm_id
)
SELECT 
  COUNT(*) AS total_admissions,
  -- First 24h percentages
  SUM(basal_bolus_24h) * 100.0 / COUNT(*) AS basal_bolus_24h_pct,
  SUM(basal_24h) * 100.0 / COUNT(*) AS basal_24h_pct,
  SUM(bolus_24h) * 100.0 / COUNT(*) AS bolus_24h_pct,
  SUM(sliding_scale_24h) * 100.0 / COUNT(*) AS sliding_scale_24h_pct,
  -- Final 12h percentages
  SUM(basal_bolus_12h) * 100.0 / COUNT(*) AS basal_bolus_12h_pct,
  SUM(basal_12h) * 100.0 / COUNT(*) AS basal_12h_pct,
  SUM(bolus_12h) * 100.0 / COUNT(*) AS bolus_12h_pct,
  SUM(sliding_scale_12h) * 100.0 / COUNT(*) AS sliding_scale_12h_pct,
  -- Percentage-point changes
  (SUM(basal_bolus_12h) - SUM(basal_bolus_24h)) * 100.0 / COUNT(*) AS basal_bolus_change,
  (SUM(basal_12h) - SUM(basal_24h)) * 100.0 / COUNT(*) AS basal_change,
  (SUM(bolus_12h) - SUM(bolus_24h)) * 100.0 / COUNT(*) AS bolus_change,
  (SUM(sliding_scale_12h) - SUM(sliding_scale_24h)) * 100.0 / COUNT(*) AS sliding_scale_change
FROM flags;