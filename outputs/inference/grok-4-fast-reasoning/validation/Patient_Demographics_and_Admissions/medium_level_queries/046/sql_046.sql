WITH icu_los AS (
  SELECT 
    i.subject_id,
    i.hadm_id, 
    SUM(i.los) AS total_los
  FROM `physionet-data.mimiciv_3_1_icu.icustays` i
  GROUP BY i.subject_id, i.hadm_id
),
eligible_adms AS (
  SELECT 
    il.subject_id,
    il.hadm_id,
    il.total_los,
    a.hospital_expire_flag,
    a.discharge_location,
    p.gender,
    p.anchor_age
  FROM icu_los il
  JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a ON il.hadm_id = a.hadm_id
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` p ON il.subject_id = p.subject_id
  WHERE p.gender = 'F'
    AND p.anchor_age BETWEEN 87 AND 97
)
SELECT 
  CASE 
    WHEN hospital_expire_flag = 1 THEN 'In-hospital death'
    WHEN discharge_location IN ('Discharged to home', 'Discharged to home with home health service') THEN 'Home'
    ELSE 'Facility'
  END AS discharge_type,
  COUNT(*) AS n,
  ROUND(AVG(total_los), 2) AS mean_los,
  ROUND(STDDEV(total_los), 2) AS sd_los,
  ROUND(100.0 * SUM(CASE WHEN total_los < 10 THEN 1 ELSE 0 END) / COUNT(*), 2) AS pct_los_lt10
FROM eligible_adms
GROUP BY discharge_type
ORDER BY n DESC;