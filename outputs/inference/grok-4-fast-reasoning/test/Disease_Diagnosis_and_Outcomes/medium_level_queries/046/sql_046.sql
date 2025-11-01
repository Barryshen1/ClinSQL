WITH hf_admissions AS (
  SELECT 
    a.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    a.hospital_expire_flag,
    p.anchor_age,
    EXISTS(SELECT 1 FROM `physionet-data.mimiciv_3_1_icu.icustays` icu WHERE icu.hadm_id = a.hadm_id) AS icu_flag,
    TIMESTAMP_DIFF(a.dischtime, a.admittime, DAY) AS los_days,
    (SELECT COUNT(*) FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d2 
     WHERE d2.subject_id = a.subject_id AND d2.hadm_id = a.hadm_id) AS comorb_count
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` p ON a.subject_id = p.subject_id
  WHERE p.gender = 'M'
    AND p.anchor_age BETWEEN 72 AND 82
    AND EXISTS (
      SELECT 1 
      FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
      WHERE d.subject_id = a.subject_id
        AND d.hadm_id = a.hadm_id
        AND (
          (d.icd_version = 'ICD-9-CM' AND d.icd_code LIKE '428%')
          OR (d.icd_version = 'ICD-10' AND d.icd_code LIKE 'I50%')
        )
    )
    AND a.dischtime > a.admittime
),
bucket_stats AS (
  SELECT 
    icu_flag,
    CASE 
      WHEN los_days <= 3 THEN '<=3'
      WHEN los_days <= 6 THEN '4-6'
      WHEN los_days <= 10 THEN '7-10'
      ELSE '>10'
    END AS los_bucket,
    COUNT(*) AS n,
    ROUND((SUM(hospital_expire_flag) * 100.0 / COUNT(*)), 2) AS bucket_mortality_rate_percent
  FROM hf_admissions
  GROUP BY icu_flag, los_bucket
),
overall_stats AS (
  SELECT 
    icu_flag,
    COUNT(*) AS total_n,
    ROUND((SUM(hospital_expire_flag) * 100.0 / COUNT(*)), 2) AS overall_mortality_rate_percent,
    PERCENTILE_CONT(los_days, 0.5) AS median_los_days,
    ROUND(AVG(comorb_count), 2) AS avg_comorb_count
  FROM hf_admissions
  GROUP BY icu_flag
)
SELECT 
  CASE WHEN b.icu_flag THEN 'ICU' ELSE 'Non-ICU' END AS cohort,
  b.los_bucket,
  b.n AS bucket_n,
  b.bucket_mortality_rate_percent,
  o.total_n,
  o.overall_mortality_rate_percent,
  o.median_los_days,
  o.avg_comorb_count
FROM bucket_stats b
JOIN overall_stats o ON b.icu_flag = o.icu_flag
ORDER BY cohort, 
  CASE b.los_bucket 
    WHEN '<=3' THEN 1
    WHEN '4-6' THEN 2
    WHEN '7-10' THEN 3
    WHEN '>10' THEN 4
  END;