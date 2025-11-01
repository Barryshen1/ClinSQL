WITH eligible_admissions AS (
  SELECT DISTINCT 
    p.subject_id,
    i.hadm_id,
    i.los,
    a.discharge_location,
    a.hospital_expire_flag
  FROM `physionet-data.mimiciv_3_1_hosp.patients` p
  INNER JOIN `physionet-data.mimiciv_3_1_icu.icustays` i
    ON p.subject_id = i.subject_id
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a
    ON i.hadm_id = a.hadm_id
  WHERE p.gender = 'F'
    AND p.anchor_age BETWEEN 63 AND 73
),
categorized_outcomes AS (
  SELECT 
    hadm_id,
    los,
    CASE 
      WHEN hospital_expire_flag = 1 THEN 'in-hospital death'
      WHEN discharge_location IN ('HOME', 'SELF CARE APARTMENT') THEN 'home'
      WHEN discharge_location LIKE '%HOSPICE%' OR discharge_location LIKE '%PALLIAT%' THEN 'hospice'
      ELSE 'other'
    END AS outcome
  FROM eligible_admissions
)
SELECT 
  outcome,
  COUNT(*) AS n,
  ROUND(AVG(los), 2) AS mean_los_days,
  ROUND(PERCENTILE_CONT(los, 0.5) OVER (PARTITION BY outcome), 2) AS median_los_days,
  ROUND(AVG(CASE WHEN los <= 10 THEN 1.0 ELSE 0 END) * 100, 2) AS pct_los_le_10_days
FROM categorized_outcomes
WHERE outcome IN ('home', 'hospice', 'in-hospital death')
GROUP BY outcome
ORDER BY 
  CASE outcome 
    WHEN 'home' THEN 1 
    WHEN 'hospice' THEN 2 
    WHEN 'in-hospital death' THEN 3 
  END;