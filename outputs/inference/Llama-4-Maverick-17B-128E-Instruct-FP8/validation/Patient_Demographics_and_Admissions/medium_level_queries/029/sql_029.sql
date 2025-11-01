WITH patient_data AS (
  SELECT 
    p.subject_id,
    p.anchor_age,
    a.hadm_id,
    i.stay_id,
    i.intime,
    i.outtime,
    DATETIME_DIFF(i.outtime, i.intime, DAY) AS los_days,
    CASE WHEN a.deathtime IS NOT NULL THEN 'Died' ELSE 'Survived' END AS survival_status
  FROM 
    `physionet-data.mimiciv_3_1_hosp.patients` p
  INNER JOIN 
    `physionet-data.mimiciv_3_1_hosp.admissions` a ON p.subject_id = a.subject_id
  INNER JOIN 
    `physionet-data.mimiciv_3_1_icu.icustays` i ON a.hadm_id = i.hadm_id
  WHERE 
    p.gender = 'F' AND p.anchor_age BETWEEN 35 AND 45
)
SELECT 
  survival_status,
  AVG(los_days) AS mean_los,
  STDDEV(los_days) AS sd_los,
  SUM(CASE WHEN los_days < 7 THEN 1 ELSE 0 END) / COUNT(*) * 100 AS percent_los_lt_7
FROM 
  patient_data
GROUP BY 
  survival_status;