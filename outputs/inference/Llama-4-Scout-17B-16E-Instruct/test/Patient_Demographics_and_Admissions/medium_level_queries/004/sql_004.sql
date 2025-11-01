WITH 
  -- Filter and calculate LOS
  patient_stays AS (
    SELECT 
      a.subject_id,
      a.hadm_id,
      a.admittime,
      a.dischtime,
      p.anchor_age,
      a.admission_type,
      a.discharge_location,
      TIMESTAMPDIFF(DAY, a.admittime, a.dischtime) AS los_days
    FROM 
      `physionet-data.mimiciv_3_1_hosp.admissions` a
    INNER JOIN 
      `physionet-data.mimiciv_3_1_hosp.patients` p 
        ON a.subject_id = p.subject_id
    WHERE 
      p.anchor_age BETWEEN 89 AND 99
      AND p.gender = 'M'
      AND a.admission_type = 'ELECTIVE'
  ),
  
  -- Categorize discharge location
  discharge_categories AS (
    SELECT 
      subject_id,
      hadm_id,
      los_days,
      discharge_location,
      CASE 
        WHEN discharge_location = 'HOME' THEN 'Home'
        WHEN discharge_location = 'HOSPICE' THEN 'Hospice'
        ELSE 'In-hospital death/other'
      END AS discharge_category
    FROM 
      patient_stays
  )

-- Calculate statistics
SELECT 
  discharge_category,
  AVG(los_days) AS mean_los,
  PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY los_days) AS median_los,
  PERCENTILE_CONT(0.75) WITHIN GROUP (ORDER BY los_days) AS p75_los,
  PERCENTILE_CONT(0.9) WITHIN GROUP (ORDER BY los_days) AS p90_los,
  SUM(CASE WHEN los_days < 5 THEN 1 ELSE 0 END) / COUNT(*) * 100 AS pct_los_lt_5_days
FROM 
  discharge_categories
GROUP BY 
  discharge_category;