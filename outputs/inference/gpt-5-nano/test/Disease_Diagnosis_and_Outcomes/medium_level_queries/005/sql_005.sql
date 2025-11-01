WITH base AS (
  SELECT
    a.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    a.hospital_expire_flag
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` AS a
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` AS p
    ON a.subject_id = p.subject_id
  WHERE p.gender = 'M'
    AND p.anchor_age BETWEEN 38 AND 48
    AND a.dischtime IS NOT NULL
),

-- 2) HF presence for the admission
hf_admissions AS (
  SELECT DISTINCT b.subject_id, b.hadm_id
  FROM base AS b
  JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` AS di
    ON di.subject_id = b.subject_id AND di.hadm_id = b.hadm_id
  JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` AS dd
    ON di.icd_code = dd.icd_code AND di.icd_version = dd.icd_version
  WHERE LOWER(dd.long_title) LIKE '%heart failure%'
),

-- 3) ICU admission indicator per hadm_id
icu_hadm AS (
  SELECT hadm_id
  FROM `physionet-data.mimiciv_3_1_icu.icustays`
  GROUP BY hadm_id
),

-- 4) LOS bucket per admission
los_bucket AS (
  SELECT b.hadm_id,
         CASE
           WHEN TIMESTAMP_DIFF(b.dischtime, b.admittime, DAY) BETWEEN 1 AND 3 THEN '1-3'
           WHEN TIMESTAMP_DIFF(b.dischtime, b.admittime, DAY) BETWEEN 4 AND 7 THEN '4-7'
           WHEN TIMESTAMP_DIFF(b.dischtime, b.admittime, DAY) >= 8 THEN '>=8'
           ELSE 'unknown'
         END AS los_bucket
  FROM base AS b
),

-- 5) Charlson-like comorbidity flags per admission
charlson_flags AS (
  SELECT di.hadm_id,
         MAX(CASE WHEN LOWER(dd.long_title) LIKE '%diabetes%' THEN 1 ELSE 0 END) AS has_diabetes,
         MAX(CASE WHEN LOWER(dd.long_title) LIKE '%renal%' OR LOWER(dd.long_title) LIKE '%kidney%' THEN 1 ELSE 0 END) AS has_renal,
         MAX(CASE WHEN LOWER(dd.long_title) LIKE '%liver%' OR LOWER(dd.long_title) LIKE '%hepatic%' THEN 1 ELSE 0 END) AS has_liver,
         MAX(CASE WHEN LOWER(dd.long_title) LIKE '%cancer%' OR LOWER(dd.long_title) LIKE '%neoplasm%' THEN 1 ELSE 0 END) AS has_cancer,
         MAX(CASE WHEN LOWER(dd.long_title) LIKE '%cerebrovascular%' OR LOWER(dd.long_title) LIKE '%stroke%' THEN 1 ELSE 0 END) AS has_cerebro,
         MAX(CASE WHEN LOWER(dd.long_title) LIKE '%copd%' OR LOWER(dd.long_title) LIKE '%chronic obstructive pulmonary disease%' THEN 1 ELSE 0 END) AS has_copd,
         MAX(CASE WHEN LOWER(dd.long_title) LIKE '%dementia%' THEN 1 ELSE 0 END) AS has_dementia,
         MAX(CASE WHEN LOWER(dd.long_title) LIKE '%peptic ulcer%' THEN 1 ELSE 0 END) AS has_peptic_ulcer,
         MAX(CASE WHEN LOWER(dd.long_title) LIKE '%aids%' THEN 1 ELSE 0 END) AS has_aids
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` AS di
  JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` AS dd
    ON di.icd_code = dd.icd_code AND di.icd_version = dd.icd_version
  WHERE di.hadm_id IN (SELECT hadm_id FROM hf_admissions)
  GROUP BY di.hadm_id
),

-- 6) Charlson-like count per admission
charlson_count AS (
  SELECT hadm_id,
         (has_diabetes + has_renal + has_liver + has_cancer + has_cerebro + has_copd + has_dementia + has_peptic_ulcer + has_aids) AS charlson_count
  FROM charlson_flags
)

-- 7) Final aggregation by ICU status, LOS bucket, and Charlson group
SELECT
  CASE WHEN i.hadm_id IS NOT NULL THEN 1 ELSE 0 END AS in_icu,
  lb.los_bucket AS los_bucket,
  CASE
     WHEN cc.charlson_count <= 3 THEN '≤3'
     WHEN cc.charlson_count BETWEEN 4 AND 5 THEN '4-5'
     ELSE '>5'
  END AS charlson_group,
  COUNT(*) AS n_admissions,
  SUM(b.hospital_expire_flag) AS deaths,
  SAFE_DIVIDE(SUM(b.hospital_expire_flag), COUNT(*)) AS mortality_rate,
  SAFE_DIVIDE(SUM(b.hospital_expire_flag), COUNT(*)) - 1.959963984540054 *
    SQRT(SAFE_DIVIDE(SUM(b.hospital_expire_flag), COUNT(*)) *
         (1 - SAFE_DIVIDE(SUM(b.hospital_expire_flag), COUNT(*))) /
         NULLIF(COUNT(*), 0)) AS ci_lower,
  SAFE_DIVIDE(SUM(b.hospital_expire_flag), COUNT(*)) +
    1.959963984540054 *
    SQRT(SAFE_DIVIDE(SUM(b.hospital_expire_flag), COUNT(*)) *
         (1 - SAFE_DIVIDE(SUM(b.hospital_expire_flag), COUNT(*))) /
         NULLIF(COUNT(*), 0)) AS ci_upper,
  AVG(cc.charlson_count) AS mean_comorbidity_count
FROM base AS b
LEFT JOIN hf_admissions AS hf ON b.hadm_id = hf.hadm_id
LEFT JOIN icu_hadm AS i ON b.hadm_id = i.hadm_id
LEFT JOIN los_bucket AS lb ON b.hadm_id = lb.hadm_id
LEFT JOIN charlson_count AS cc ON b.hadm_id = cc.hadm_id
GROUP BY 1, 2, 3
ORDER BY 1, 2, 3;