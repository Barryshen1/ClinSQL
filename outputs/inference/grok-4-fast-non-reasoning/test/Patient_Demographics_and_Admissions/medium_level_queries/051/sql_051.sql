WITH cohort AS (
  SELECT 
    p.subject_id,
    p.gender,
    p.anchor_age,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    a.hospital_expire_flag,
    DATE_DIFF(a.dischtime, a.admittime, DAY) AS los_days
  FROM 
    `physionet-data.mimiciv_3_1_hosp.patients` p
  INNER JOIN 
    `physionet-data.mimiciv_3_1_hosp.admissions` a
  ON 
    p.subject_id = a.subject_id
  WHERE 
    p.gender = 'M'
    AND p.anchor_age BETWEEN 68 AND 78
    AND a.admission_location LIKE '%EMERGENCY%'
    AND a.dischtime IS NOT NULL
)

SELECT 
  hospital_expire_flag AS discharge_status,
  ROUND(AVG(los_days), 2) AS mean_los_days,
  ROUND(STDDEV(los_days), 2) AS sd_los_days,
  ROUND(AVG(CASE WHEN los_days <= 7 THEN 1.0 ELSE 0 END) * 100, 2) AS pct_los_le_7_days
FROM 
  cohort
WHERE 
  anchor_age = 73
GROUP BY 
  hospital_expire_flag
ORDER BY 
  hospital_expire_flag;