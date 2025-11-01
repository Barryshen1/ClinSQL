WITH eligible_patients AS (
  SELECT 
    p.subject_id,
    p.anchor_age,
    a.hadm_id,
    a.admittime,
    a.dischtime
  FROM 
    physionet-data.mimiciv_3_1_hosp.patients p
  INNER JOIN 
    physionet-data.mimiciv_3_1_hosp.admissions a
    ON p.subject_id = a.subject_id
  WHERE 
    p.gender = 'M'
    AND p.anchor_age BETWEEN 63 AND 73
    AND a.admittime IS NOT NULL
    AND a.dischtime IS NOT NULL
    AND a.dischtime >= a.admittime + INTERVAL 1 HOUR
),

t2dm_hf_admissions AS (
  SELECT DISTINCT
    ep.subject_id,
    ep.hadm_id,
    ep.admittime,
    ep.dischtime
  FROM 
    eligible_patients ep
  INNER JOIN 
    physionet-data.mimiciv_3_1_hosp.diagnoses_icd di
    ON ep.hadm_id = di.hadm_id
  INNER JOIN 
    physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses did
    ON di.icd_code = did.icd_code AND di.icd_version = did.icd_version
  WHERE 
    (LOWER(did.long_title) LIKE '%type 2 diabetes mellitus%'
     OR LOWER(did.long_title) LIKE '%diabetes mellitus type 2%')
    AND (
      LOWER(did.long_title) LIKE '%heart failure%' 
      OR LOWER(did.long_title) LIKE '%congestive heart failure%'
      OR LOWER(did.long_title) LIKE '%chronic heart failure%'
      OR LOWER(did.long_title) LIKE '%acute heart failure%'
    )
),

medication_flags AS (
  SELECT 
    th.hadm_id,
    p.starttime,
    CASE 
      WHEN LOWER(p.drug) LIKE '%insulin%' 
        OR LOWER(p.drug) LIKE '%lispro%' 
        OR LOWER(p.drug) LIKE '%glargine%' 
        OR LOWER(p.drug) LIKE '%detemir%' 
        OR LOWER(p.drug) LIKE '%degludec%' 
        OR LOWER(p.drug) LIKE '%regular%' 
        OR LOWER(p.drug) LIKE '%nph%' 
        OR LOWER(p.drug) LIKE '%novolog%' 
        OR LOWER(p.drug) LIKE '%humalog%' 
        OR LOWER(p.drug) LIKE '%fiasp%' 
        OR LOWER(p.drug) LIKE '%afrezza%' 
      THEN 1 
      ELSE 0 
    END AS has_insulin,
    CASE 
      WHEN LOWER(p.drug) LIKE '%metformin%' 
        OR LOWER(p.drug) LIKE '%glipizide%' 
        OR LOWER(p.drug) LIKE '%glyburide%' 
        OR LOWER(p.drug) LIKE '%gliclazide%' 
        OR LOWER(p.drug) LIKE '%glimepiride%' 
        OR LOWER(p.drug) LIKE '%repaglinide%' 
        OR LOWER(p.drug) LIKE '%nateglinide%' 
        OR LOWER(p.drug) LIKE '%pioglitazone%' 
        OR LOWER(p.drug) LIKE '%rosiglitazone%' 
        OR LOWER(p.drug) LIKE '%sitagliptin%' 
        OR LOWER(p.drug) LIKE '%saxagliptin%' 
        OR LOWER(p.drug) LIKE '%linagliptin%' 
        OR LOWER(p.drug) LIKE '%empagliflozin%' 
        OR LOWER(p.drug) LIKE '%canagliflozin%' 
        OR LOWER(p.drug) LIKE '%dapagliflozin%' 
        OR LOWER(p.drug) LIKE '%chlorpropamide%' 
        OR LOWER(p.drug) LIKE '%tolbutamide%' 
        OR LOWER(p.drug) LIKE '%acetohexamide%' 
        OR LOWER(p.drug) LIKE '%tolazamide%' 
      THEN 1 
      ELSE 0 
    END AS has_oral_agent
  FROM 
    t2dm_hf_admissions th
  INNER JOIN 
    physionet-data.mimiciv_3_1_hosp.prescriptions p
    ON th.hadm_id = p.hadm_id
  WHERE 
    p.starttime IS NOT NULL
),

first_24h AS (
  SELECT 
    hadm_id,
    MAX(has_insulin) AS insulin_first_24h,
    MAX(has_oral_agent) AS oral_first_24h
  FROM 
    medication_flags
  WHERE 
    starttime >= admittime 
    AND starttime <= admittime + INTERVAL 24 HOUR
  GROUP BY 
    hadm_id
),

final_24h AS (
  SELECT 
    hadm_id,
    MAX(has_insulin) AS insulin_final_24h,
    MAX(has_oral_agent) AS oral_final_24h
  FROM 
    medication_flags
  WHERE 
    starttime >= dischtime - INTERVAL 24 HOUR
    AND starttime <= dischtime
  GROUP BY 
    hadm_id
),

combined AS (
  SELECT 
    th.hadm_id,
    COALESCE(f.insulin_first_24h, 0) AS insulin_first_24h,
    COALESCE(f.oral_first_24h, 0) AS oral_first_24h,
    COALESCE(fn.insulin_final_24h, 0) AS insulin_final_24h,
    COALESCE(fn.oral_final_24h, 0) AS oral_final_24h
  FROM 
    t2dm_hf_admissions th
  LEFT JOIN 
    first_24h f ON th.hadm_id = f.hadm_id
  LEFT JOIN 
    final_24h fn ON th.hadm_id = fn.hadm_id
)

SELECT 
  ROUND(100.0 * SUM(insulin_first_24h) / COUNT(*), 2) AS insulin_prevalence_first_24h_pct,
  ROUND(100.0 * SUM(insulin_final_24h) / COUNT(*), 2) AS insulin_prevalence_final_24h_pct,
  ROUND(100.0 * (SUM(insulin_final_24h) - SUM(insulin_first_24h)) / COUNT(*), 2) AS insulin_net_change_pp,
  ROUND(100.0 * SUM(oral_first_24h) / COUNT(*), 2) AS oral_prevalence_first_24h_pct,
  ROUND(100.0 * SUM(oral_final_24h) / COUNT(*), 2) AS oral_prevalence_final_24h_pct,
  ROUND(100.0 * (SUM(oral_final_24h) - SUM(oral_first_24h)) / COUNT(*), 2) AS oral_net_change_pp
FROM 
  combined;