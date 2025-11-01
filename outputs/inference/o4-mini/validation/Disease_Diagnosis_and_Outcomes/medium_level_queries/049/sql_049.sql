WITH 
-- 1. Base admissions of 56-year-old men (51–61)
adm_male AS (
  SELECT
    a.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    a.hospital_expire_flag,
    p.anchor_age
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON a.subject_id = p.subject_id
  WHERE p.gender = 'M'
    AND p.anchor_age BETWEEN 51 AND 61
),

-- 2. Classify STEMI vs NSTEMI
mi_class AS (
  SELECT
    d.hadm_id,
    MAX(CASE WHEN LOWER(di.long_title) LIKE '%stemi%' THEN 1 ELSE 0 END) AS has_stemi,
    MAX(CASE WHEN LOWER(di.long_title) LIKE '%nstemi%' THEN 1 ELSE 0 END) AS has_nstemi
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
  JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` di
    ON d.icd_code = di.icd_code
   AND d.icd_version = di.icd_version
  GROUP BY d.hadm_id
),
cohort AS (
  SELECT
    a.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    a.hospital_expire_flag,
    CASE
      WHEN m.has_stemi = 1 AND m.has_nstemi = 0 THEN 'STEMI'
      WHEN m.has_nstemi = 1 AND m.has_stemi = 0 THEN 'NSTEMI'
      ELSE NULL
    END AS mi_type
  FROM adm_male a
  LEFT JOIN mi_class m
    ON a.hadm_id = m.hadm_id
  WHERE (m.has_stemi + m.has_nstemi) = 1
),

-- 3. Comorbidity counts, CKD and diabetes flags
comorb AS (
  SELECT
    c.*,
    DATE_DIFF(c.dischtime, c.admittime, DAY) AS los_days,
    -- bucket LOS
    CASE
      WHEN DATE_DIFF(c.dischtime, c.admittime, DAY) BETWEEN 1 AND 2 THEN '1-2'
      WHEN DATE_DIFF(c.dischtime, c.admittime, DAY) BETWEEN 3 AND 5 THEN '3-5'
      WHEN DATE_DIFF(c.dischtime, c.admittime, DAY) BETWEEN 6 AND 9 THEN '6-9'
      ELSE '>=10'
    END AS los_bucket,
    -- comorbidity counts excluding acute MI codes
    COUNT(DISTINCT CASE 
      WHEN (d.icd_version = 9 AND NOT STARTS_WITH(d.icd_code, '410'))
        AND (d.icd_version = 10 AND NOT STARTS_WITH(d.icd_code, 'I21'))
      THEN d.icd_code ELSE NULL END) 
      OVER (PARTITION BY c.hadm_id) AS comorb_count,
    -- CKD flag
    MAX(CASE
      WHEN (d.icd_version = 9 AND STARTS_WITH(d.icd_code, '585'))
        OR (d.icd_version = 10 AND STARTS_WITH(d.icd_code, 'N18'))
      THEN 1 ELSE 0 END) 
      OVER (PARTITION BY c.hadm_id) AS ckd_flag,
    -- Diabetes flag
    MAX(CASE
      WHEN (d.icd_version = 9 AND STARTS_WITH(d.icd_code, '250'))
        OR (d.icd_version = 10 AND (STARTS_WITH(d.icd_code, 'E10') OR STARTS_WITH(d.icd_code, 'E11')))
      THEN 1 ELSE 0 END) 
      OVER (PARTITION BY c.hadm_id) AS dm_flag
  FROM cohort c
  LEFT JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
    ON c.hadm_id = d.hadm_id
),

-- 4. Final bucketing of comorbidity counts
final_prep AS (
  SELECT
    mi_type,
    los_bucket,
    CASE
      WHEN comorb_count <= 1 THEN '0-1'
      WHEN comorb_count = 2 THEN '2'
      ELSE '>=3'
    END AS comorb_bucket,
    hospital_expire_flag,
    ckd_flag,
    dm_flag
  FROM comorb
)

-- 5. Aggregate
SELECT
  mi_type,
  los_bucket,
  comorb_bucket,
  COUNT(*) AS N,
  ROUND(100 * SUM(hospital_expire_flag) / COUNT(*), 1) AS pct_mortality,
  ROUND(100 * SUM(ckd_flag) / COUNT(*), 1) AS pct_CKD,
  ROUND(100 * SUM(dm_flag) / COUNT(*), 1) AS pct_diabetes
FROM final_prep
GROUP BY mi_type, los_bucket, comorb_bucket
ORDER BY mi_type, los_bucket, comorb_bucket;