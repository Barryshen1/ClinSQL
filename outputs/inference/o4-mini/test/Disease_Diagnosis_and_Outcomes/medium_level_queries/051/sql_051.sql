WITH cohort AS (
  -- Step 1: base admissions for 51–61-year-old men with primary T81% diagnosis
  SELECT
    a.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    a.hospital_expire_flag,
    TIMESTAMP_DIFF(a.dischtime, a.admittime, DAY) AS los_days,
    p.anchor_age
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON a.subject_id = p.subject_id
  JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
    ON a.hadm_id = d.hadm_id
   AND d.seq_num = 1
   AND d.icd_version = 10
   AND STARTS_WITH(d.icd_code, 'T81')
  WHERE p.gender = 'M'
    AND p.anchor_age BETWEEN 51 AND 61
),
icu_flagged AS (
  -- Step 2: mark ICU vs non-ICU
  SELECT
    c.*,
    CASE WHEN icu.hadm_id IS NOT NULL THEN 'ICU' ELSE 'Non-ICU' END AS icu_group
  FROM cohort c
  LEFT JOIN (
    SELECT DISTINCT hadm_id
    FROM `physionet-data.mimiciv_3_1_icu.icustays`
  ) icu
    ON c.hadm_id = icu.hadm_id
),
comorb AS (
  -- Step 4: build Charlson score and CKD/Diabetes flags
  SELECT
    icu.subject_id,
    icu.hadm_id,
    icu.admittime,
    icu.dischtime,
    icu.hospital_expire_flag,
    icu.los_days,
    icu.icu_group,
    -- CKD flag if any N18% diagnosis
    MAX(CASE WHEN d.icd_version = 10 AND STARTS_WITH(d.icd_code, 'N18') THEN 1 ELSE 0 END) AS ckd_flag,
    -- Diabetes flag if any E10% or E11% diagnosis
    MAX(CASE WHEN d.icd_version = 10 AND (STARTS_WITH(d.icd_code, 'E10') OR STARTS_WITH(d.icd_code, 'E11')) THEN 1 ELSE 0 END) AS diabetes_flag,
    -- Charlson weights for a few conditions (illustrative)
    MAX(CASE WHEN d.icd_version = 10 AND (STARTS_WITH(d.icd_code,'I21') OR STARTS_WITH(d.icd_code,'I22')) THEN 1 ELSE 0 END)
      + MAX(CASE WHEN d.icd_version = 10 AND STARTS_WITH(d.icd_code,'I50') THEN 1 ELSE 0 END)
      + MAX(CASE WHEN d.icd_version = 10 AND STARTS_WITH(d.icd_code,'N18') THEN 2 ELSE 0 END)
      + MAX(CASE WHEN d.icd_version = 10 AND (STARTS_WITH(d.icd_code,'E10') OR STARTS_WITH(d.icd_code,'E11')) THEN 1 ELSE 0 END)
      AS charlson_score
  FROM icu_flagged icu
  LEFT JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
    ON icu.hadm_id = d.hadm_id
  GROUP BY 1,2,3,4,5,6,7
),
buckets AS (
  -- Step 3 & final bucketing
  SELECT
    subject_id,
    hadm_id,
    admittime,
    dischtime,
    hospital_expire_flag,
    los_days,
    icu_group,
    ckd_flag,
    diabetes_flag,
    charlson_score,
    CASE
      WHEN los_days BETWEEN 1 AND 2 THEN '1-2'
      WHEN los_days BETWEEN 3 AND 5 THEN '3-5'
      WHEN los_days BETWEEN 6 AND 9 THEN '6-9'
      WHEN los_days >= 10 THEN '>=10'
      ELSE '0'
    END AS los_bucket,
    CASE
      WHEN charlson_score BETWEEN 0 AND 1 THEN '0-1'
      WHEN charlson_score = 2 THEN '2'
      WHEN charlson_score >= 3 THEN '>=3'
    END AS charlson_bucket
  FROM comorb
)
SELECT
  icu_group,
  los_bucket,
  charlson_bucket,
  COUNT(*) AS N_admissions,
  ROUND(100.0 * SUM(hospital_expire_flag) / COUNT(*), 1) AS mortality_pct,
  APPROX_QUANTILES(los_days, 2)[OFFSET(1)] AS median_los_days,
  ROUND(100.0 * SUM(ckd_flag) / COUNT(*), 1) AS ckd_prevalence_pct,
  ROUND(100.0 * SUM(diabetes_flag) / COUNT(*), 1) AS diabetes_prevalence_pct
FROM buckets
WHERE los_bucket <> '0'    -- exclude zero or negative LOS if any
GROUP BY icu_group, los_bucket, charlson_bucket
ORDER BY icu_group, los_bucket, charlson_bucket;