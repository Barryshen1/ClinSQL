WITH cohort AS (
  -- Base cohort: male, age 38-48, primary HF diagnosis
  SELECT 
    p.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    a.hospital_expire_flag,
    p.anchor_age,
    p.gender
  FROM `physionet-data.mimiciv_3_1_hosp.patients` p
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a
    ON p.subject_id = a.subject_id
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
    ON a.subject_id = d.subject_id AND a.hadm_id = d.hadm_id
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` icd
    ON d.icd_code = icd.icd_code AND d.icd_version = icd.icd_version
  WHERE p.gender = 'M'
    AND p.anchor_age BETWEEN 38 AND 48
    AND d.seq_num = 1
    AND (
      (d.icd_version = 'ICD-9' AND d.icd_code LIKE '428%') OR
      (d.icd_version = 'ICD-10' AND d.icd_code LIKE 'I50%')
    )
),

icu_classification AS (
  -- Classify admissions with any ICU stay using EXISTS to avoid duplication
  SELECT 
    c.subject_id,
    c.hadm_id,
    CASE 
      WHEN EXISTS (
        SELECT 1 FROM `physionet-data.mimiciv_3_1_icu.icustays` i
        WHERE i.subject_id = c.subject_id AND i.hadm_id = c.hadm_id
      ) THEN 'ICU' 
      ELSE 'No ICU' 
    END AS icu_stratum
  FROM cohort c
),

charlson_comorb AS (
  -- Compute unweighted comorbidity count (proxy for Charlson; excludes HF; key categories only)
  SELECT 
    c.subject_id,
    c.hadm_id,
    COUNT(DISTINCT comorb_type) AS comorbidity_count
  FROM cohort c
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
    ON c.subject_id = d.subject_id AND c.hadm_id = d.hadm_id
    AND NOT (d.seq_num = 1 AND (
      (d.icd_version = 'ICD-9' AND d.icd_code LIKE '428%') OR
      (d.icd_version = 'ICD-10' AND d.icd_code LIKE 'I50%')
    ))  -- Exclude primary HF from count
  CROSS JOIN UNNEST([
    STRUCT(
      CASE 
        WHEN (d.icd_version = 'ICD-9' AND d.icd_code LIKE '410%') OR (d.icd_version = 'ICD-10' AND d.icd_code LIKE 'I21%') THEN 'MI'
        WHEN (d.icd_version = 'ICD-9' AND d.icd_code LIKE '443%') OR (d.icd_version = 'ICD-10' AND d.icd_code LIKE 'I70%') THEN 'PVD'
        WHEN (d.icd_version = 'ICD-9' AND d.icd_code LIKE '331%') OR (d.icd_version = 'ICD-10' AND d.icd_code LIKE 'F01%') THEN 'Dementia'
        WHEN (d.icd_version = 'ICD-9' AND (d.icd_code LIKE '490%' OR d.icd_code LIKE '491%' OR d.icd_code LIKE '492%' OR d.icd_code LIKE '496%')) 
             OR (d.icd_version = 'ICD-10' AND d.icd_code LIKE 'J40%-J47%') THEN 'COPD'
        WHEN (d.icd_version = 'ICD-9' AND (d.icd_code LIKE '2500%' OR d.icd_code LIKE '2501%' OR d.icd_code LIKE '2502%' OR d.icd_code LIKE '2503%')) 
             OR (d.icd_version = 'ICD-10' AND (d.icd_code LIKE 'E10%' OR d.icd_code LIKE 'E11%')) THEN 'DM'
        WHEN (d.icd_version = 'ICD-9' AND d.icd_code LIKE '342%') OR (d.icd_version = 'ICD-10' AND d.icd_code LIKE 'G81%') THEN 'Hemiplegia'
        WHEN (d.icd_version = 'ICD-9' AND (d.icd_code LIKE '582%' OR d.icd_code LIKE '583%' OR d.icd_code LIKE '585%' OR d.icd_code LIKE '586%' OR d.icd_code LIKE '588%')) 
             OR (d.icd_version = 'ICD-10' AND d.icd_code LIKE 'N18%') THEN 'Renal'
        WHEN (d.icd_version = 'ICD-9' AND d.icd_code BETWEEN '140' AND '208') OR (d.icd_version = 'ICD-10' AND d.icd_code LIKE 'C00%-D48%') THEN 'Cancer'
        ELSE NULL 
      END AS comorb_type
    )
  ]) 
  WHERE comorb_type IS NOT NULL
  GROUP BY c.subject_id, c.hadm_id
),

stratified_data AS (
  SELECT 
    c.*,
    ic.icu_stratum,
    DATE_DIFF(c.dischtime, c.admittime, DAY) AS los_days,
    CASE 
      WHEN DATE_DIFF(c.dischtime, c.admittime, DAY) BETWEEN 1 AND 3 THEN '1-3'
      WHEN DATE_DIFF(c.dischtime, c.admittime, DAY) BETWEEN 4 AND 7 THEN '4-7'
      ELSE '>=8'
    END AS los_stratum,
    CASE 
      WHEN COALESCE(cc.comorbidity_count, 0) <= 3 THEN '<=3'
      WHEN COALESCE(cc.comorbidity_count, 0) BETWEEN 4 AND 5 THEN '4-5'
      ELSE '>5'
    END AS charlson_stratum,
    COALESCE(cc.comorbidity_count, 0) AS comorb_count
  FROM cohort c
  INNER JOIN icu_classification ic
    ON c.subject_id = ic.subject_id AND c.hadm_id = ic.hadm_id
  LEFT JOIN charlson_comorb cc
    ON c.subject_id = cc.subject_id AND c.hadm_id = cc.hadm_id
),

aggregated AS (
  SELECT 
    icu_stratum,
    los_stratum,
    charlson_stratum,
    COUNT(*) AS n_admissions,
    SUM(hospital_expire_flag) AS deaths,
    AVG(comorb_count) AS mean_comorbidity_count,
    -- Wilson score 95% CI components
    1.96 AS z,
    SAFE_DIVIDE(SUM(hospital_expire_flag), COUNT(*)) AS p,
    COUNT(*) AS n
  FROM stratified_data
  GROUP BY icu_stratum, los_stratum, charlson_stratum
)

SELECT 
  icu_stratum,
  los_stratum,
  charlson_stratum,
  n_admissions,
  ROUND(p * 100, 2) AS mortality_pct,
  ROUND(
    100 * ((p + (z*z)/(2*n)) / (1 + (z*z)/n) - 
           z * SQRT((p*(1-p)/n) + (z*z)/(4*n*n)) / (1 + (z*z)/n)), 2
  ) AS ci_lower_pct,
  ROUND(
    100 * ((p + (z*z)/(2*n)) / (1 + (z*z)/n) + 
           z * SQRT((p*(1-p)/n) + (z*z)/(4*n*n)) / (1 + (z*z)/n)), 2
  ) AS ci_upper_pct,
  ROUND(mean_comorbidity_count, 2) AS mean_comorbidity_count
FROM aggregated
ORDER BY 
  CASE icu_stratum WHEN 'ICU' THEN 1 ELSE 2 END,
  CASE los_stratum WHEN '1-3' THEN 1 WHEN '4-7' THEN 2 ELSE 3 END,
  CASE charlson_stratum WHEN '<=3' THEN 1 WHEN '4-5' THEN 2 ELSE 3 END;