WITH cohort AS (
  -- Base cohort: women 69-79
  SELECT 
    p.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    a.hospital_expire_flag,
    p.anchor_age,
    DATE_DIFF(DATE(a.dischtime), DATE(a.admittime), DAY) + 1 AS los_days
  FROM `physionet-data.mimiciv_3_1_hosp.patients` p
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a
    ON p.subject_id = a.subject_id
  WHERE p.gender = 'F'
    AND p.anchor_age BETWEEN 69 AND 79
    AND a.hospital_expire_flag IS NOT NULL  -- Ensure valid admissions
),

gi_classify AS (
  -- Classify GI bleed type using ICD codes (fixed for no-decimal format)
  SELECT 
    c.*,
    CASE 
      WHEN MAX(CASE 
        WHEN REGEXP_CONTAINS(icd.icd_code, r'^(K25|K26|K27|K92[0-2])') THEN 1 
        ELSE 0 
      END) > 0 THEN 'Upper'
      WHEN MAX(CASE 
        WHEN REGEXP_CONTAINS(icd.icd_code, r'^K92[45]') THEN 1 
        ELSE 0 
      END) > 0 THEN 'Lower'
      ELSE 'Other'
    END AS gi_bleed_type
  FROM cohort c
  LEFT JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` icd
    ON c.hadm_id = icd.hadm_id
  GROUP BY 
    c.subject_id, c.hadm_id, c.admittime, c.dischtime, c.hospital_expire_flag, 
    c.anchor_age, c.los_days
),

filtered_cohort AS (
  -- Filter to only upper/lower GI bleed admissions
  SELECT *
  FROM gi_classify
  WHERE gi_bleed_type IN ('Upper', 'Lower')
),

icu_flags AS (
  -- Flag day-1 ICU and any ICU
  SELECT 
    fc.*,
    CASE 
      WHEN EXISTS (
        SELECT 1 
        FROM `physionet-data.mimiciv_3_1_icu.icustays` i
        WHERE i.subject_id = fc.subject_id 
          AND i.hadm_id = fc.hadm_id 
          AND i.intime <= TIMESTAMP_ADD(fc.admittime, INTERVAL 1 DAY)
      ) THEN 'Yes' ELSE 'No' 
    END AS day1_icu,
    CASE 
      WHEN EXISTS (
        SELECT 1 
        FROM `physionet-data.mimiciv_3_1_icu.icustays` i
        WHERE i.subject_id = fc.subject_id AND i.hadm_id = fc.hadm_id
      ) THEN 1 ELSE 0 
    END AS any_icu
  FROM filtered_cohort fc
),

los_buckets AS (
  -- Bucket LOS
  SELECT 
    *,
    CASE 
      WHEN los_days <= 2 THEN '1-2'
      WHEN los_days <= 5 THEN '3-5'
      WHEN los_days <= 9 THEN '6-9'
      ELSE '>=10'
    END AS los_bucket
  FROM icu_flags
)

-- Main: Mortality % by GI type, LOS bucket, day-1 ICU
SELECT 
  gi_bleed_type,
  los_bucket,
  day1_icu,
  COUNT(*) AS total_admissions,
  SUM(hospital_expire_flag) AS deaths,
  ROUND(SUM(hospital_expire_flag) * 100.0 / COUNT(*), 2) AS mortality_pct
FROM los_buckets
GROUP BY gi_bleed_type, los_bucket, day1_icu
ORDER BY gi_bleed_type, 
  CASE los_bucket 
    WHEN '1-2' THEN 1 
    WHEN '3-5' THEN 2 
    WHEN '6-9' THEN 3 
    ELSE 4 
  END, 
  day1_icu DESC;

-- Query 2: Overall ICU admission rates by GI type
WITH cohort AS (
  -- Base cohort: women 69-79 (reuse logic)
  SELECT 
    p.subject_id,
    a.hadm_id,
    a.admittime,
    p.anchor_age
  FROM `physionet-data.mimiciv_3_1_hosp.patients` p
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a
    ON p.subject_id = a.subject_id
  WHERE p.gender = 'F'
    AND p.anchor_age BETWEEN 69 AND 79
),

gi_classify AS (
  -- Classify GI bleed type (reuse fixed logic)
  SELECT 
    c.*,
    CASE 
      WHEN MAX(CASE 
        WHEN REGEXP_CONTAINS(icd.icd_code, r'^(K25|K26|K27|K92[0-2])') THEN 1 
        ELSE 0 
      END) > 0 THEN 'Upper'
      WHEN MAX(CASE 
        WHEN REGEXP_CONTAINS(icd.icd_code, r'^K92[45]') THEN 1 
        ELSE 0 
      END) > 0 THEN 'Lower'
      ELSE 'Other'
    END AS gi_bleed_type
  FROM cohort c
  LEFT JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` icd
    ON c.hadm_id = icd.hadm_id
  GROUP BY c.subject_id, c.hadm_id, c.admittime, c.anchor_age
),

filtered_cohort AS (
  -- Filter to only upper/lower GI bleed admissions
  SELECT *
  FROM gi_classify
  WHERE gi_bleed_type IN ('Upper', 'Lower')
),

icu_flags AS (
  -- Flag any ICU
  SELECT 
    fc.*,
    CASE 
      WHEN EXISTS (
        SELECT 1 
        FROM `physionet-data.mimiciv_3_1_icu.icustays` i
        WHERE i.subject_id = fc.subject_id AND i.hadm_id = fc.hadm_id
      ) THEN 1 ELSE 0 
    END AS any_icu
  FROM filtered_cohort fc
)

-- ICU admission rates by GI type
SELECT 
  gi_bleed_type,
  COUNT(*) AS total_admissions,
  SUM(any_icu) AS icu_admissions,
  ROUND(SUM(any_icu) * 100.0 / COUNT(*), 2) AS icu_rate_pct
FROM icu_flags
GROUP BY gi_bleed_type
ORDER BY gi_bleed_type;