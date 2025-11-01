WITH eligible_admissions AS (
  SELECT 
    a.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    a.hospital_expire_flag,
    a.discharge_location,
    TIMESTAMP_DIFF(a.dischtime, a.admittime, DAY) AS los_days,
    CASE
      WHEN a.hospital_expire_flag = 1 THEN 'in-hospital death'
      WHEN a.discharge_location IN ('Home', 'Home Health Care') THEN 'home'
      WHEN a.discharge_location IN ('Skilled Nursing Facility', 'Rehab/Distinct Part Hosp', 'Long Term Care Hospital') THEN 'SNF/rehab/LTACH'
      ELSE NULL
    END AS outcome
  FROM 
    `physionet-data.mimiciv_3_1_hosp.admissions` a
  INNER JOIN 
    `physionet-data.mimiciv_3_1_hosp.patients` p
  ON a.subject_id = p.subject_id
  WHERE 
    p.gender = 'M'
    AND p.anchor_age BETWEEN 88 AND 98
    AND a.admission_type = 'ELECTIVE'
    AND a.dischtime IS NOT NULL
    AND a.hadm_id IS NOT NULL
    AND TIMESTAMP_DIFF(a.dischtime, a.admittime, DAY) > 0
)
SELECT 
  outcome,
  AVG(los_days) AS mean_los,
  APPROX_QUANTILES(los_days, 100)[OFFSET(50)] AS p50_los,
  APPROX_QUANTILES(los_days, 100)[OFFSET(75)] AS p75_los,
  APPROX_QUANTILES(los_days, 100)[OFFSET(90)] AS p90_los,
  (SUM(CASE WHEN los_days <= 7 THEN 1 ELSE 0 END) * 100.0 / COUNT(*)) AS pct_los_le_7_days
FROM eligible_admissions
WHERE outcome IS NOT NULL
GROUP BY outcome
ORDER BY 
  CASE outcome
    WHEN 'home' THEN 1
    WHEN 'SNF/rehab/LTACH' THEN 2
    WHEN 'in-hospital death' THEN 3
  END;