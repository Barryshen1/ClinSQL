WITH cohort AS (
  SELECT 
    p.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    p.gender,
    p.anchor_age,
    a.admission_location,
    a.hospital_expire_flag,
    TIMESTAMP_DIFF(a.dischtime, a.admittime, HOUR) / 24.0 AS los_days
  FROM 
    `physionet-data.mimiciv_3_1_hosp.patients` p
  INNER JOIN 
    `physionet-data.mimiciv_3_1_hosp.admissions` a
  ON 
    p.subject_id = a.subject_id
  WHERE 
    p.gender = 'M'
    AND p.anchor_age BETWEEN 68 AND 78
    AND a.admission_location = 'EMERGENCY DEPARTMENT'
    AND a.dischtime IS NOT NULL
)
SELECT 
  CASE 
    WHEN hospital_expire_flag = 1 THEN 'Dead' 
    ELSE 'Alive' 
  END AS discharge_status,
  AVG(los_days) AS mean_los_days,
  STDDEV(los_days) AS sd_los_days,
  (COUNTIF(los_days <= 7) * 100.0 / COUNT(*)) AS percent_los_le_7_days
FROM 
  cohort
GROUP BY 
  discharge_status
ORDER BY 
  discharge_status;