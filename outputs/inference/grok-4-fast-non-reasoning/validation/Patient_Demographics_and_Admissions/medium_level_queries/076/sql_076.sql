WITH inpatient_cohort AS (
  SELECT 
    a.hadm_id,
    a.admittime,
    a.dischtime,
    a.hospital_expire_flag,
    p.gender,
    p.anchor_age,
    DATE_DIFF(DATE(a.dischtime), DATE(a.admittime), DAY) AS los_days
  FROM 
    `physionet-data.mimiciv_3_1_hosp.admissions` a
  INNER JOIN 
    `physionet-data.mimiciv_3_1_hosp.patients` p
  ON a.subject_id = p.subject_id
  WHERE 
    p.anchor_age BETWEEN 83 AND 93
    AND p.gender = 'M'
    AND a.admission_type IN ('ELECTIVE', 'EMERGENCY', 'URGENT')
    AND a.dischtime > a.admittime
)
SELECT 
  hospital_expire_flag,
  COUNT(*) AS n_patients,
  AVG(los_days) AS mean_los_days,
  APPROX_QUANTILES(los_days, 100)[SAFE_OFFSET(50)] AS p50_los_days,
  APPROX_QUANTILES(los_days, 100)[SAFE_OFFSET(75)] AS p75_los_days,
  APPROX_QUANTILES(los_days, 100)[SAFE_OFFSET(90)] AS p90_los_days,
  -- Percentile rank of 5-day LOS: approx quantile where value closest to 5
  (SELECT AS VALUE approx_quantile
   FROM UNNEST(APPROX_QUANTILES(los_days, 100)) AS q WITH OFFSET off
   ORDER BY ABS(q - 5)
   LIMIT 1) * 100 AS pct_rank_5day_los_approx
FROM 
  inpatient_cohort
GROUP BY 
  hospital_expire_flag
ORDER BY 
  hospital_expire_flag;