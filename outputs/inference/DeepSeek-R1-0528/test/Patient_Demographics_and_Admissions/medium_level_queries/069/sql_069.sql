WITH cohort AS (
  SELECT 
    p.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    a.hospital_expire_flag,
    p.anchor_age + (EXTRACT(YEAR FROM a.admittime) - p.anchor_year) AS age_adm
  FROM `physionet-data.mimiciv_3_1_hosp.patients` p
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a
    ON p.subject_id = a.subject_id
  INNER JOIN (
    SELECT 
      hadm_id, 
      curr_service,
      ROW_NUMBER() OVER (PARTITION BY hadm_id ORDER BY transfertime) AS rn
    FROM `physionet-data.mimiciv_3_1_hosp.services`
  ) s
    ON a.hadm_id = s.hadm_id AND s.rn = 1
  WHERE 
    p.gender = 'F'
    AND a.admission_type = 'EMERGENCY'
    AND s.curr_service = 'MEDICAL'
),
filtered_cohort AS (
  SELECT 
    subject_id,
    hadm_id,
    hospital_expire_flag,
    TIMESTAMP_DIFF(dischtime, admittime, HOUR) / 24.0 AS los_days
  FROM cohort
  WHERE age_adm BETWEEN 59 AND 69
),
proportion_stats AS (
  SELECT 
    hospital_expire_flag,
    COUNT(*) AS total_admissions,
    COUNTIF(los_days >= 7) AS count_los_ge7,
    COUNTIF(los_days >= 7) / COUNT(*) AS proportion
  FROM filtered_cohort
  GROUP BY hospital_expire_flag
),
percentile_rank AS (
  SELECT 
    SAFE_DIVIDE(COUNTIF(los_days <= 7) * 100.0, COUNT(*)) AS percentile_rank_7
  FROM filtered_cohort
)
SELECT 
  'proportion' AS metric,
  hospital_expire_flag,
  total_admissions,
  count_los_ge7,
  proportion,
  NULL AS percentile_rank_7
FROM proportion_stats
UNION ALL
SELECT 
  'percentile_rank' AS metric,
  NULL AS hospital_expire_flag,
  NULL AS total_admissions,
  NULL AS count_los_ge7,
  NULL AS proportion,
  percentile_rank_7
FROM percentile_rank;