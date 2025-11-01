WITH patient_cohort AS (
  SELECT 
    adm.hadm_id,
    pat.gender,
    adm.admittime,
    adm.dischtime,
    adm.discharge_location,
    adm.hospital_expire_flag,
    DATETIME_DIFF(adm.dischtime, adm.admittime, HOUR) / 24 AS los_days
  FROM 
    `physionet-data.mimiciv_3_1_hosp.admissions` adm
  INNER JOIN 
    `physionet-data.mimiciv_3_1_hosp.patients` pat ON adm.subject_id = pat.subject_id
  WHERE 
    pat.gender = 'M'
    AND pat.anchor_age BETWEEN 57 AND 67
    AND adm.admission_location = 'EMERGENCY ROOM ADMIT'
),
discharge_status AS (
  SELECT 
    hadm_id,
    los_days,
    CASE
      WHEN discharge_location = 'HOME' THEN 'Home'
      WHEN discharge_location LIKE '%HOSPICE%' THEN 'Hospice'
      WHEN hospital_expire_flag = 1 THEN 'In-hospital death'
      ELSE 'Other'
    END AS discharge_category
  FROM 
    patient_cohort
),
cohort_counts AS (
  SELECT 
    COUNT(*) AS total_count,
    SUM(CASE WHEN los_days <= 10 THEN 1 ELSE 0 END) AS count_los_leq_10
  FROM 
    patient_cohort
)
SELECT 
  'Statistics' AS type,
  discharge_category,
  COUNT(*) AS count,
  AVG(los_days) AS mean_los,
  APPROX_QUANTILES(los_days, 100)[OFFSET(50)] AS median_los,
  APPROX_QUANTILES(los_days, 100)[OFFSET(75)] AS p75_los,
  APPROX_QUANTILES(los_days, 100)[OFFSET(90)] AS p90_los,
  NULL AS percentile_rank_10days
FROM 
  discharge_status
WHERE 
  discharge_category IN ('Home', 'Hospice', 'In-hospital death')
GROUP BY 
  discharge_category
UNION ALL
SELECT 
  'Percentile Rank' AS type,
  '10 days' AS discharge_category,
  NULL AS count,
  NULL AS mean_los,
  NULL AS median_los,
  NULL AS p75_los,
  NULL AS p90_los,
  CASE 
    WHEN total_count = 0 THEN NULL 
    ELSE count_los_leq_10 / total_count 
  END AS percentile_rank_10days
FROM 
  cohort_counts;