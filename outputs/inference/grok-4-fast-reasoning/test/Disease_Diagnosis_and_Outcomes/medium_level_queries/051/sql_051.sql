WITH eligible_admissions AS (
  SELECT DISTINCT 
    a.subject_id, 
    a.hadm_id, 
    a.admittime, 
    a.dischtime, 
    a.hospital_expire_flag,
    p.gender, 
    p.anchor_age
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` p 
    ON a.subject_id = p.subject_id
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` prim_d 
    ON a.hadm_id = prim_d.hadm_id AND prim_d.seq_num = 1
  WHERE p.gender = 'M'
    AND p.anchor_age BETWEEN 51 AND 61
    AND DATEDIFF(a.dischtime, a.admittime, DAY) >= 1  -- LOS >=1 day
    AND (
      (prim_d.icd_version = 9 
       AND (prim_d.icd_code LIKE '996%' OR prim_d.icd_code LIKE '997%' 
            OR prim_d.icd_code LIKE '998%' OR prim_d.icd_code LIKE '999%')) 
      OR 
      (prim_d.icd_version = 10 
       AND (prim_d.icd_code LIKE 'T80%' OR prim_d.icd_code LIKE 'T81%' 
            OR prim_d.icd_code LIKE 'T82%' OR prim_d.icd_code LIKE 'T83%' 
            OR prim_d.icd_code LIKE 'T84%' OR prim_d.icd_code LIKE 'T85%' 
            OR prim_d.icd_code LIKE 'T86%' OR prim_d.icd_code LIKE 'T87%' 
            OR prim_d.icd_code LIKE 'T88%'))
    )
),
cohort AS (
  SELECT 
    ea.*,
    DATEDIFF(ea.dischtime, ea.admittime, DAY) AS los_days,
    CASE 
      WHEN EXISTS (
        SELECT 1 FROM `physionet-data.mimiciv_3_1_icu.icustays` i 
        WHERE i.subject_id = ea.subject_id AND i.hadm_id = ea.hadm_id
      ) THEN 'ICU' 
      ELSE 'Non-ICU' 
    END AS icu_flag
  FROM eligible_admissions ea
),
with_diagnoses AS (
  SELECT 
    c.*,
    d.icd_code, 
    d.icd_version
  FROM cohort c
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d 
    ON c.hadm_id = d.hadm_id  -- All diagnoses for comorbidities
),
-- Partial Charlson: MI, CHF, diabetes, renal (moderate/severe); see TODO for full
charlson_score AS (
  SELECT 
    hadm_id, 
    COALESCE(SUM(score), 0) AS charlson
  FROM (
    -- Myocardial Infarction (weight 1)
    SELECT hadm_id, 1 AS score
    FROM with_diagnoses
    WHERE (
      (icd_version = 9 AND (icd_code LIKE '410%' OR icd_code = '412')) 
      OR 
      (icd_version = 10 AND (icd_code LIKE 'I21%' OR icd_code LIKE 'I22%' OR icd_code LIKE 'I25.2%'))
    )
    GROUP BY hadm_id
    
    UNION ALL
    
    -- Congestive Heart Failure (weight 1)
    SELECT hadm_id, 1 AS score
    FROM with_diagnoses
    WHERE (
      (icd_version = 9 AND (
        icd_code LIKE '428%' OR icd_code IN ('402.01', '402.11', '402.91', '404.01', '404.11', '404.91', 
                                            '425.4', '425.5', '425.7', '425.8', '429.0', '429.1')
      )) 
      OR 
      (icd_version = 10 AND (
        icd_code LIKE 'I09.9' OR icd_code LIKE 'I11.0%' OR icd_code LIKE 'I13.0%' OR icd_code = 'I13.2' 
        OR icd_code LIKE 'I25.5%' OR icd_code LIKE 'I42%' OR icd_code LIKE 'I43%' OR icd_code LIKE 'I50%'
      ))
    )
    GROUP BY hadm_id
    
    UNION ALL
    
    -- Diabetes (any; weight 1; approximate, excludes complications distinction)
    SELECT hadm_id, 1 AS score
    FROM with_diagnoses
    WHERE (
      (icd_version = 9 AND icd_code LIKE '250.%') 
      OR 
      (icd_version = 10 AND icd_code LIKE 'E1[0-4]%') 
    )
    GROUP BY hadm_id
    
    UNION ALL
    
    -- Moderate/Severe Renal Disease (weight 2; broader than simple CKD)
    SELECT hadm_id, 2 AS score
    FROM with_diagnoses
    WHERE (
      (icd_version = 9 AND (icd_code LIKE '582%' OR icd_code LIKE '583.[0-7]%' OR icd_code LIKE '585%' OR icd_code = '586' OR icd_code IN ('V42.0', 'V45.11', 'V45.12', 'V56%'))) 
      OR 
      (icd_version = 10 AND (icd_code LIKE 'I12%' OR icd_code LIKE 'I13%' OR icd_code LIKE 'N18%' OR icd_code LIKE 'N19%' OR icd_code IN ('N25.4', 'Z94.0', 'Z49.2')))
    )
    GROUP BY hadm_id
    
    -- TODO: Add remaining components (e.g., PVD, dementia, COPD, malignancy, etc.) using Quan mappings for full accuracy
  )
  GROUP BY hadm_id
),
has_diabetes AS (
  SELECT 
    hadm_id, 
    MAX(CASE WHEN is_diabetes = 1 THEN 1 ELSE 0 END) AS has_diabetes
  FROM (
    SELECT 
      hadm_id,
      CASE 
        WHEN (icd_version = 9 AND icd_code LIKE '250.%') 
             OR (icd_version = 10 AND icd_code LIKE 'E1[0-4]%') 
        THEN 1 ELSE 0 
      END AS is_diabetes
    FROM with_diagnoses
  )
  GROUP BY hadm_id
),
has_ckd AS (
  SELECT 
    hadm_id, 
    MAX(CASE WHEN is_ckd = 1 THEN 1 ELSE 0 END) AS has_ckd
  FROM (
    SELECT 
      hadm_id,
      CASE 
        WHEN (icd_version = 9 AND icd_code LIKE '585%') 
             OR (icd_version = 10 AND icd_code LIKE 'N18%') 
        THEN 1 ELSE 0 
      END AS is_ckd
    FROM with_diagnoses
  )
  GROUP BY hadm_id
),
stratified_data AS (
  SELECT 
    c.*,
    cs.charlson,
    hd.has_diabetes,
    hc.has_ckd,
    CASE 
      WHEN c.los_days BETWEEN 1 AND 2 THEN '1-2'
      WHEN c.los_days BETWEEN 3 AND 5 THEN '3-5'
      WHEN c.los_days BETWEEN 6 AND 9 THEN '6-9'
      ELSE '>=10'
    END AS los_bin,
    CASE 
      WHEN COALESCE(cs.charlson, 0) <= 1 THEN '0-1'
      WHEN COALESCE(cs.charlson, 0) = 2 THEN '2'
      ELSE '>=3'
    END AS charlson_bin
  FROM cohort c
  LEFT JOIN charlson_score cs ON c.hadm_id = cs.hadm_id
  LEFT JOIN has_diabetes hd ON c.hadm_id = hd.hadm_id
  LEFT JOIN has_ckd hc ON c.hadm_id = hc.hadm_id
)
SELECT 
  icu_flag,
  los_bin,
  charlson_bin,
  COUNT(*) AS n,
  ROUND(100.0 * SUM(hospital_expire_flag) / COUNT(*), 2) AS mortality_pct,
  PERCENTILE_CONT(los_days, 0.5) AS median_los_days,
  ROUND(100.0 * SUM(COALESCE(has_diabetes, 0)) / COUNT(*), 2) AS diabetes_prevalence_pct,
  ROUND(100.0 * SUM(COALESCE(has_ckd, 0)) / COUNT(*), 2) AS ckd_prevalence_pct
FROM stratified_data
GROUP BY icu_flag, los_bin, charlson_bin
ORDER BY icu_flag, los_bin, charlson_bin;