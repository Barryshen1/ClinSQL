WITH 
  -- Filter and calculate LOS
  patient_stays AS (
    SELECT 
      a.hadm_id,
      a.admittime,
      a.dischtime,
      a.discharge_location,
      a.hospital_expire_flag,
      p.gender,
      p.anchor_age,
      TIMESTAMP_DIFF(a.dischtime, a.admittime, DAY) AS los_days
    FROM 
      `physionet-data.mimiciv_3_1_hosp.admissions` a
    INNER JOIN 
      `physionet-data.mimiciv_3_1_hosp.patients` p
    ON 
      a.subject_id = p.subject_id
    WHERE 
      p.gender = 'F'
      AND p.anchor_age BETWEEN 50 AND 60
      AND a.admission_location = 'ED'
  ),
  
  -- Categorize discharge outcomes
  discharge_outcomes AS (
    SELECT 
      hadm_id,
      admittime,
      dischtime,
      los_days,
      CASE 
        WHEN hospital_expire_flag = 1 THEN 'In-hospital death'
        WHEN discharge_location = 'Home' THEN 'Home'
        WHEN discharge_location LIKE '%Hospice%' THEN 'Hospice'
        ELSE 'Other'
      END AS discharge_outcome
    FROM 
      patient_stays
  )

-- Calculate mean, SD, and percentage of LOS ≤ 10 days by discharge outcome
SELECT 
  discharge_outcome,
  AVG(los_days) AS mean_los,
  STDDEV(los_days) AS sd_los,
  COUNT(CASE WHEN los_days <= 10 THEN 1 END) / COUNT(*) * 100 AS pct_los_10_days
FROM 
  discharge_outcomes
WHERE 
  discharge_outcome IN ('Home', 'Hospice', 'In-hospital death')
GROUP BY 
  discharge_outcome;