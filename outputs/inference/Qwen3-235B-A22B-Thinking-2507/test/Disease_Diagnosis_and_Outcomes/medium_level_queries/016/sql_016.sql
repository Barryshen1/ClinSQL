WITH base_population AS (
  SELECT 
    a.hadm_id,
    a.subject_id,
    a.admittime,
    a.dischtime,
    a.hospital_expire_flag,
    p.anchor_age + (EXTRACT(YEAR FROM a.admittime) - p.anchor_year) AS age,
    TIMESTAMP_DIFF(a.dischtime, a.admittime, SECOND) / 86400.0 AS los
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON a.subject_id = p.subject_id
  WHERE p.gender = 'M'
    AND a.dischtime IS NOT NULL
    AND p.anchor_age + (EXTRACT(YEAR FROM a.admittime) - p.anchor_year) BETWEEN 40 AND 50
),
diagnoses_summary AS (
  SELECT 
    hadm_id,
    MAX(CASE 
          WHEN (icd_version = 9 AND icd_code LIKE '410%') 
            OR (icd_version = 10 AND (icd_code LIKE 'I21%' OR icd_code LIKE 'I22%')) 
          THEN 1 ELSE 0 END) AS has_ami,
    MAX(CASE 
          WHEN (icd_version = 9 AND (icd_code LIKE '785.5%' OR icd_code LIKE '518.8%'))
            OR (icd_version = 10 AND (icd_code LIKE 'R57%' OR icd_code LIKE 'J96%'))
          THEN 1 ELSE 0 END) AS has_shock_rf
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd`
  GROUP BY hadm_id
),
cohort AS (
  SELECT b.*
  FROM base_population b
  INNER JOIN diagnoses_summary d 
    ON b.hadm_id = d.hadm_id
  WHERE d.has_ami = 1 
    AND d.has_shock_rf = 0
),
cohort_with_icu AS (
  SELECT 
    c.*,
    CASE WHEN EXISTS (
           SELECT 1 
           FROM `physionet-data.mimiciv_3_1_icu.icustays` i 
           WHERE i.hadm_id = c.hadm_id 
             AND i.intime < TIMESTAMP_ADD(c.admittime, INTERVAL 1 DAY)
         ) THEN 1 ELSE 0 END AS icu_day1
  FROM cohort c
)
SELECT
  CASE WHEN los <= 5 THEN '≤5' ELSE '>5' END AS los_group,
  icu_day1,
  COUNT(*) AS n,
  AVG(hospital_expire_flag) * 100 AS mortality_rate,
  APPROX_QUANTILES(los, 100)[OFFSET(50)] AS median_los
FROM cohort_with_icu
GROUP BY los_group, icu_day1
ORDER BY los_group, icu_day1;