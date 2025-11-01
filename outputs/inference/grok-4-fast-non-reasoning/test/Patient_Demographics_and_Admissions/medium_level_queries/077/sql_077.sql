WITH eligible_admissions AS (
  SELECT 
    p.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    a.hospital_expire_flag,
    DATE_DIFF(DATE(a.dischtime), DATE(a.admittime), DAY) AS los_days,
    p.anchor_age,
    p.gender,
    a.admission_location,
    a.admission_type
  FROM 
    `physionet-data.mimiciv_3_1_hosp.patients` p
  INNER JOIN 
    `physionet-data.mimiciv_3_1_hosp.admissions` a
  ON 
    p.subject_id = a.subject_id
  WHERE 
    p.gender = 'M'
    AND p.anchor_age BETWEEN 41 AND 51
    AND EXTRACT(YEAR FROM a.admittime) = p.anchor_year
    AND a.admission_location = 'EMERGENCY ROOM'
    AND a.admission_type IN ('EMERGENCY', 'URGENT', 'ELECTIVE')
    AND a.dischtime IS NOT NULL
)

SELECT 
  hospital_expire_flag,
  ROUND(AVG(los_days), 2) AS mean_los_days,
  APPROX_QUANTILES(los_days, 2)[OFFSET(1)] AS median_los_days,
  ROUND((SUM(CASE WHEN los_days <= 5 THEN 1 ELSE 0 END) * 100.0 / COUNT(*)), 2) AS pct_los_le_5_days
FROM 
  eligible_admissions
GROUP BY 
  hospital_expire_flag
ORDER BY 
  hospital_expire_flag;