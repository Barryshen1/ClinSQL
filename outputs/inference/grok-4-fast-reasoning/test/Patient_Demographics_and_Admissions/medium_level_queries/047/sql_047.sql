WITH filtered_admissions AS (
  SELECT 
    a.hospital_expire_flag,
    a.discharge_location,
    TIMESTAMP_DIFF(a.dischtime, a.admittime, HOUR) / 24.0 AS los
  FROM `physionet-data.mimiciv_3_1_hosp.patients` p
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a 
    ON p.subject_id = a.subject_id
  WHERE p.gender = 'F'
    AND p.anchor_age BETWEEN 52 AND 62
    AND a.admission_location = 'TRANSFER'
    AND a.dischtime IS NOT NULL
    AND TIMESTAMP_DIFF(a.dischtime, a.admittime, HOUR) > 0
    AND (
      a.hospital_expire_flag = 1 
      OR a.discharge_location = 'DISCHARGED TO HOME'
      OR a.discharge_location IN (
        'DISCHARGED TO SNF', 
        'TRANSFERRED TO SNF', 
        'DISCHARGED TO REHAB / DISTINCT PART HOSP', 
        'TRANSFERRED TO REHAB', 
        'TRANSFERRED TO LTAC', 
        'LONG TERM CARE HOSPITAL'
      )
    )
)
SELECT 
  CASE 
    WHEN hospital_expire_flag = 1 THEN 'in-hospital death'
    WHEN discharge_location = 'DISCHARGED TO HOME' THEN 'discharged home'
    ELSE 'facility'
  END AS discharge_type,
  ROUND(AVG(los), 2) AS mean_los_days,
  ROUND(STDDEV_SAMP(los), 2) AS sd_los_days,
  ROUND(100.0 * AVG(CASE WHEN los <= 5 THEN 1 ELSE 0 END), 2) AS percentile_rank_5day_los
FROM filtered_admissions
GROUP BY discharge_type
HAVING COUNT(*) > 0
ORDER BY 
  CASE discharge_type
    WHEN 'discharged home' THEN 1
    WHEN 'facility' THEN 2
    WHEN 'in-hospital death' THEN 3
  END;