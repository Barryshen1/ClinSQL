WITH sepsis_cohort AS (
  SELECT DISTINCT 
    a.subject_id,
    a.hadm_id,
    p.gender,
    p.anchor_age,
    a.hospital_expire_flag,
    DATE_DIFF(DATE(a.dischtime), DATE(a.admittime), DAY) AS los_days,
    CASE 
      WHEN DATE_DIFF(DATE(a.dischtime), DATE(a.admittime), DAY) <= 7 THEN '<=7 days'
      ELSE '>7 days'
    END AS los_group
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON a.subject_id = p.subject_id
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
    ON a.subject_id = d.subject_id AND a.hadm_id = d.hadm_id
  WHERE p.anchor_age BETWEEN 50 AND 60
    AND p.gender = 'M'
    AND d.icd_version = '10'
    AND d.seq_num = 1
    AND (
      -- Sepsis codes (A41.*, R65.2 without shock)
      (d.icd_code LIKE 'A41.%' AND d.icd_code NOT LIKE 'A41.9')
      OR (d.icd_code LIKE 'R65.2%' AND d.icd_code != 'R65.21')
    )
),
icu_status AS (
  SELECT 
    sc.*,
    CASE 
      WHEN EXISTS (
        SELECT 1 
        FROM `physionet-data.mimiciv_3_1_icu.icustays` i
        WHERE i.subject_id = sc.subject_id 
          AND i.hadm_id = sc.hadm_id 
          AND DATE(i.intime) = DATE(TIMESTAMP(a.admittime))
      ) THEN 'ICU Day 1'
      ELSE 'No ICU Day 1'
    END AS icu_day1_status
  FROM sepsis_cohort sc
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a
    ON sc.hadm_id = a.hadm_id
)
SELECT 
  los_group,
  icu_day1_status,
  ROUND(AVG(CASE WHEN hospital_expire_flag = 1 THEN 1.0 ELSE 0.0 END) * 100, 2) AS mortality_pct,
  PERCENTILE_CONT(los_days, 0.5) AS median_los_days
FROM icu_status
GROUP BY los_group, icu_day1_status
ORDER BY los_group, icu_day1_status;