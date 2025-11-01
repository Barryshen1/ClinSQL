WITH cohort AS (
  SELECT 
    p.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    DATE_DIFF(a.dischtime, a.admittime, DAY) AS los_days,
    a.hospital_expire_flag
  FROM 
    `physionet-data.mimiciv_3_1_hosp.patients` p
  INNER JOIN 
    `physionet-data.mimiciv_3_1_hosp.admissions` a
  ON 
    p.subject_id = a.subject_id
  WHERE 
    p.gender = 'M'
    AND p.anchor_age BETWEEN 41 AND 51
    AND a.admission_location = 'EMERGENCY ROOM'
    AND a.dischtime IS NOT NULL
)
SELECT 
  hospital_expire_flag,
  AVG(los_days) AS mean_los_days,
  APPROX_QUANTILES(los_days, 2)[OFFSET(1)] AS median_los_days,
  SAFE_DIVIDE(COUNTIF(los_days <= 5) * 100.0, COUNT(*)) AS pct_le_5day_los
FROM 
  cohort
GROUP BY 
  hospital_expire_flag
ORDER BY 
  hospital_expire_flag;