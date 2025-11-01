WITH age_calc AS (
  SELECT 
    a.subject_id, 
    a.hadm_id, 
    a.admittime, 
    a.dischtime, 
    a.discharge_location, 
    a.hospital_expire_flag,
    p.gender,
    TIMESTAMP_DIFF(a.dischtime, a.admittime, DAY) AS los_days,
    EXTRACT(YEAR FROM a.admittime) - p.anchor_year + p.anchor_age AS age_at_admit
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON a.subject_id = p.subject_id
  WHERE p.gender = 'M'
    AND EXTRACT(YEAR FROM a.admittime) - p.anchor_year + p.anchor_age BETWEEN 75 AND 85
    AND a.dischtime IS NOT NULL
),
categorized AS (
  SELECT 
    *,
    CASE 
      WHEN hospital_expire_flag = 1 THEN 'In-hospital death'
      WHEN discharge_location = 'HOME' THEN 'Discharged home'
      WHEN discharge_location IN ('SNF', 'REHAB', 'LTC') THEN 'To facility'
      ELSE NULL 
    END AS category
  FROM age_calc
  WHERE CASE 
          WHEN hospital_expire_flag = 1 THEN 'In-hospital death'
          WHEN discharge_location = 'HOME' THEN 'Discharged home'
          WHEN discharge_location IN ('SNF', 'REHAB', 'LTC') THEN 'To facility'
          ELSE NULL 
        END IS NOT NULL
)
SELECT 
  category,
  COUNT(*) AS total_admissions,
  COUNTIF(los_days >= 7) AS num_los_ge7,
  COUNTIF(los_days >= 7) * 1.0 / COUNT(*) AS proportion_los_ge7_days,
  COUNTIF(los_days <= 7) * 100.0 / COUNT(*) AS percentile_rank_7day_los
FROM categorized
GROUP BY category
ORDER BY 
  CASE category
    WHEN 'Discharged home' THEN 1
    WHEN 'To facility' THEN 2
    WHEN 'In-hospital death' THEN 3
  END;