WITH cohort AS (
  SELECT 
    a.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    a.admission_type,
    a.discharge_location,
    a.hospital_expire_flag,
    p.gender,
    p.anchor_age,
    p.anchor_year,
    TIMESTAMP_DIFF(a.dischtime, a.admittime, DAY) AS los_days,
    (EXTRACT(YEAR FROM a.admittime) - p.anchor_year + p.anchor_age) AS age_at_admit
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` p 
    ON a.subject_id = p.subject_id
  WHERE a.dischtime IS NOT NULL
    AND p.gender = 'M'
    AND a.admission_type = 'ELECTIVE'
    AND (EXTRACT(YEAR FROM a.admittime) - p.anchor_year + p.anchor_age) BETWEEN 80 AND 90
),
categorized AS (
  SELECT 
    *,
    CASE 
      WHEN hospital_expire_flag = 1 THEN 'In-hospital death'
      WHEN discharge_location IN ('Hospice', 'Hospice / Inpatient') THEN 'Hospice'
      WHEN discharge_location IN ('Disch to home', 'Discharged to home') THEN 'Home'
      ELSE NULL
    END AS discharge_category
  FROM cohort
)
SELECT 
  discharge_category,
  AVG(los_days) AS mean_los_days,
  APPROX_QUANTILES(los_days, 100)[OFFSET(25)] AS p25_los_days,
  APPROX_QUANTILES(los_days, 100)[OFFSET(50)] AS median_los_days,
  APPROX_QUANTILES(los_days, 100)[OFFSET(75)] AS p75_los_days,
  APPROX_QUANTILES(los_days, 100)[OFFSET(90)] AS p90_los_days,
  ROUND(AVG(CASE WHEN los_days <= 14 THEN 1.0 ELSE 0 END) * 100, 2) AS pct_le_14_days
FROM categorized
WHERE discharge_category IS NOT NULL
GROUP BY discharge_category
ORDER BY 
  CASE discharge_category
    WHEN 'Home' THEN 1
    WHEN 'Hospice' THEN 2
    WHEN 'In-hospital death' THEN 3
  END;