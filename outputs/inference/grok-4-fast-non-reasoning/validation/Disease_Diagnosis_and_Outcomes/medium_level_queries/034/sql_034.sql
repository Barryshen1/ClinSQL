WITH cohort AS (
  SELECT 
    a.hadm_id,
    a.admittime,
    a.dischtime,
    a.deathtime,
    a.hospital_expire_flag,
    DATE_DIFF(a.dischtime, a.admittime, DAY) AS los_days,
    CASE 
      WHEN DATE_DIFF(a.dischtime, a.admittime, DAY) < 8 THEN '<8 days'
      ELSE '≥8 days'
    END AS los_cat
  FROM `physionet-data.mimiciv_3_1_hosp.patients` p
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a
    ON p.subject_id = a.subject_id
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
    ON a.hadm_id = d.hadm_id
  WHERE p.gender = 'F'
    AND p.anchor_age BETWEEN 70 AND 80
    AND d.icd_version = '10'
    AND d.icd_code LIKE 'I50%'
    AND d.seq_num = 1  -- Primary diagnosis
)

SELECT 
  -- LOS <8 days
  '<8 days' AS metric,
  COUNT(DISTINCT hadm_id) AS n_admissions,
  ROUND(SUM(CASE WHEN hospital_expire_flag = 1 THEN 1 ELSE 0 END) * 100.0 / COUNT(DISTINCT hadm_id), 2) AS mortality_rate_percent,
  NULL AS median_time_to_death_days

UNION ALL

SELECT 
  -- LOS ≥8 days
  '≥8 days' AS metric,
  COUNT(DISTINCT hadm_id) AS n_admissions,
  ROUND(SUM(CASE WHEN hospital_expire_flag = 1 THEN 1 ELSE 0 END) * 100.0 / COUNT(DISTINCT hadm_id), 2) AS mortality_rate_percent,
  NULL AS median_time_to_death_days

FROM cohort
WHERE los_cat = '≥8 days'

UNION ALL

SELECT 
  -- Total non-survivors (N)
  'Total non-survivors (N)' AS metric,
  COUNT(DISTINCT hadm_id) AS n_admissions,
  NULL AS mortality_rate_percent,
  NULL AS median_time_to_death_days

FROM cohort
WHERE hospital_expire_flag = 1

UNION ALL

SELECT 
  -- Median time-to-death (days)
  'Median time-to-death (days)' AS metric,
  NULL AS n_admissions,
  NULL AS mortality_rate_percent,
  (SELECT APPROX_QUANTILES(DATE_DIFF(deathtime, admittime, DAY), 2)[OFFSET(1)] 
   FROM cohort 
   WHERE hospital_expire_flag = 1 AND deathtime IS NOT NULL) AS median_time_to_death_days

ORDER BY 
  CASE metric
    WHEN '<8 days' THEN 1
    WHEN '≥8 days' THEN 2
    WHEN 'Total non-survivors (N)' THEN 3
    ELSE 4
  END;