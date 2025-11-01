WITH cohort AS (
  SELECT 
    a.hadm_id, 
    a.hospital_expire_flag, 
    DATE_DIFF(CAST(a.dischtime AS DATE), CAST(a.admittime AS DATE), DAY) AS los_days
  FROM 
    `physionet-data.mimiciv_3_1_hosp.admissions` a
  INNER JOIN 
    `physionet-data.mimiciv_3_1_hosp.patients` p 
    ON a.subject_id = p.subject_id
  WHERE 
    p.gender = 'F'
    AND p.anchor_age BETWEEN 35 AND 45
    AND EXISTS (
      SELECT 1 
      FROM `physionet-data.mimiciv_3_1_icu.icustays` i 
      WHERE i.hadm_id = a.hadm_id
    )
)
SELECT 
  hospital_expire_flag,
  ROUND(AVG(los_days), 2) AS mean_los_days,
  ROUND(STDDEV(los_days), 2) AS sd_los_days,
  ROUND(COUNT(CASE WHEN los_days < 7 THEN 1 END) * 100.0 / COUNT(*), 2) AS pct_los_lt7_days
FROM 
  cohort
GROUP BY 
  hospital_expire_flag
ORDER BY 
  hospital_expire_flag;