WITH eligible_admissions AS (
  SELECT 
    p.subject_id,
    a.hadm_id,
    p.gender,
    p.anchor_age,
    a.admittime,
    a.dischtime,
    a.discharge_location,
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
    AND p.anchor_age BETWEEN 75 AND 85
    AND (p.dod IS NULL OR p.dod > a.dischtime)
),
categorized_outcomes AS (
  SELECT 
    *,
    CASE 
      WHEN hospital_expire_flag = 1 THEN 'In-hospital death'
      WHEN discharge_location IN ('HOME', 'REHAB/DISTINCT PART HOSP') THEN 'Discharged home'
      WHEN discharge_location IN ('SNF', 'LONG TERM CARE HOSPITAL') THEN 'To facility'
      ELSE 'Other'
    END AS outcome_category
  FROM 
    eligible_admissions
)
SELECT 
  CASE 
    WHEN hospital_expire_flag = 1 THEN 'In-hospital death'
    WHEN discharge_location IN ('HOME', 'REHAB/DISTINCT PART HOSP') THEN 'Discharged home'
    WHEN discharge_location IN ('SNF', 'LONG TERM CARE HOSPITAL') THEN 'To facility'
    ELSE 'Other'
  END AS outcome_category,
  COUNT(*) AS num_admissions,
  AVG(CASE WHEN los_days >= 7 THEN 1.0 ELSE 0 END) AS prop_los_ge7,
  -- Percentile rank of a 7-day LOS: % of admissions with LOS < 7 days
  (SUM(CASE WHEN los_days < 7 THEN 1 ELSE 0 END) * 100.0 / COUNT(*)) AS percentile_rank_los7
FROM 
  categorized_outcomes
WHERE 
  CASE 
    WHEN hospital_expire_flag = 1 THEN 'In-hospital death'
    WHEN discharge_location IN ('HOME', 'REHAB/DISTINCT PART HOSP') THEN 'Discharged home'
    WHEN discharge_location IN ('SNF', 'LONG TERM CARE HOSPITAL') THEN 'To facility'
    ELSE 'Other'
  END IN ('Discharged home', 'To facility', 'In-hospital death')
GROUP BY 
  hospital_expire_flag, discharge_location
ORDER BY 
  num_admissions DESC;