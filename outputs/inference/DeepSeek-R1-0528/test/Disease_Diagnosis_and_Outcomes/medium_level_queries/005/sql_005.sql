WITH
-- Male patients aged 38-48 with heart failure admissions
hf_admissions AS (
  SELECT
    p.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    a.hospital_expire_flag
  FROM `physionet-data.mimiciv_3_1_hosp.patients` p
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a
    ON p.subject_id = a.subject_id
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
    ON a.hadm_id = d.hadm_id
  WHERE
    p.gender = 'M'
    AND (EXTRACT(YEAR FROM a.admittime) - (p.anchor_year - p.anchor_age)) BETWEEN 38 AND 48
    AND (
      (d.icd_version = 9 AND d.icd_code LIKE '428%')
      OR (d.icd_version = 10 AND d.icd_code LIKE 'I50%')
    )
  GROUP BY p.subject_id, a.hadm_id, a.admittime, a.dischtime, a.hospital_expire_flag
),

-- Charlson comorbidity mapping (simplified example)
charlson_map AS (
  SELECT '410%' AS icd_code, 9 AS icd_version, 1 AS weight, 'MI' AS category
  UNION ALL SELECT '412%', 9, 1, 'MI'
  UNION ALL SELECT 'I21%', 10, 1, 'MI'
  UNION ALL SELECT 'I22%', 10, 1, 'MI'
  UNION ALL SELECT 'I252', 10, 1, 'MI'
  UNION ALL SELECT '428%', 9, 1, 'CHF'
  UNION ALL SELECT 'I50%', 10, 1, 'CHF'
  UNION ALL SELECT '250.00' , 9, 1, 'DM'
  UNION ALL SELECT 'E10%', 10, 1, 'DM'
  -- Add all other categories here
),

-- Calculate Charlson index per admission
charlson_data AS (
  SELECT
    hf.hadm_id,
    COALESCE(SUM(cm.weight), 0) AS charlson_index,
    COUNT(DISTINCT cm.category) AS comorbidity_count
  FROM hf_admissions hf
  LEFT JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
    ON hf.hadm_id = d.hadm_id
  LEFT JOIN charlson_map cm
    ON d.icd_code LIKE cm.icd_code
    AND d.icd_version = cm.icd_version
  GROUP BY hf.hadm_id
),

-- Add ICU flag, LOS, and Charlson groups
cohort AS (
  SELECT
    hf.*,
    cd.charlson_index,
    cd.comorbidity_count,
    CASE
      WHEN EXISTS (
        SELECT 1 
        FROM `physionet-data.mimiciv_3_1_icu.icustays` i 
        WHERE i.hadm_id = hf.hadm_id
      ) THEN 'ICU'
      ELSE 'no ICU'
    END AS icu_flag,
    DATE_DIFF(hf.dischtime, hf.admittime, DAY) AS los_days,
    CASE
      WHEN DATE_DIFF(hf.dischtime, hf.admittime, DAY) BETWEEN 1 AND 3 THEN '1-3'
      WHEN DATE_DIFF(hf.dischtime, hf.admittime, DAY) BETWEEN 4 AND 7 THEN '4-7'
      WHEN DATE_DIFF(hf.dischtime, hf.admittime, DAY) >= 8 THEN '>=8'
      ELSE 'Other'
    END AS los_group,
    CASE
      WHEN cd.charlson_index <= 3 THEN '<=3'
      WHEN cd.charlson_index BETWEEN 4 AND 5 THEN '4-5'
      WHEN cd.charlson_index > 5 THEN '>5'
    END AS charlson_group
  FROM hf_admissions hf
  LEFT JOIN charlson_data cd
    ON hf.hadm_id = cd.hadm_id
)

-- Final aggregation with corrected CI calculations
SELECT
  icu_flag,
  los_group,
  charlson_group,
  COUNT(*) AS total_admissions,
  SUM(hospital_expire_flag) AS deaths,
  AVG(hospital_expire_flag) * 100 AS mortality_percent,
  ( 
    AVG(hospital_expire_flag) 
    - 1.96 * SQRT( (AVG(hospital_expire_flag) * (1 - AVG(hospital_expire_flag)) / COUNT(*) ) 
  ) * 100 AS lower_ci_95,
  ( 
    AVG(hospital_expire_flag) 
    + 1.96 * SQRT( (AVG(hospital_expire_flag) * (1 - AVG(hospital_expire_flag)) / COUNT(*) ) 
  ) * 100 AS upper_ci_95,
  AVG(comorbidity_count) AS mean_comorbidity_count
FROM cohort
GROUP BY icu_flag, los_group, charlson_group
ORDER BY icu_flag, los_group, charlson_group;